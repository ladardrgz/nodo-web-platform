-- Accesos rápidos personales del OWNER. No pertenecen a la organización.
create table public.user_quick_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  service text not null check (service in ('GOOGLE', 'GMAIL', 'YOUTUBE', 'WHATSAPP', 'FACEBOOK', 'INSTAGRAM', 'TELEGRAM')),
  url text not null check (char_length(url) between 12 and 2048),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, service)
);

create index user_quick_links_user_enabled_idx on public.user_quick_links (user_id, enabled);
create trigger user_quick_links_set_updated_at before update on public.user_quick_links for each row execute function public.set_updated_at();

create function public.quick_link_url_allowed(p_service text, p_url text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_host text;
begin
  if p_url !~ '^https://[^[:space:]]+$' or char_length(p_url) > 2048 then return false; end if;
  v_host := lower(split_part(split_part(substring(p_url from 9), '/', 1), ':', 1));
  if v_host = '' or v_host like '%@%' then return false; end if;
  return case upper(p_service)
    when 'GOOGLE' then v_host = 'google.com' or v_host like '%.google.com'
    when 'GMAIL' then v_host = 'mail.google.com' or v_host like '%.mail.google.com'
    when 'YOUTUBE' then v_host in ('youtube.com', 'youtu.be') or v_host like '%.youtube.com'
    when 'WHATSAPP' then v_host in ('wa.me', 'whatsapp.com') or v_host like '%.whatsapp.com'
    when 'FACEBOOK' then v_host = 'facebook.com' or v_host like '%.facebook.com'
    when 'INSTAGRAM' then v_host = 'instagram.com' or v_host like '%.instagram.com'
    when 'TELEGRAM' then v_host in ('t.me', 'telegram.me') or v_host like '%.telegram.me'
    else false
  end;
end;
$$;

alter table public.user_quick_links
  add constraint user_quick_links_url_allowed check (public.quick_link_url_allowed(service, url));

alter table public.user_quick_links enable row level security;
grant select, insert, update, delete on public.user_quick_links to authenticated;

create policy user_quick_links_select_own on public.user_quick_links for select to authenticated using (user_id = auth.uid());
create policy user_quick_links_insert_own on public.user_quick_links for insert to authenticated with check (user_id = auth.uid());
create policy user_quick_links_update_own on public.user_quick_links for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy user_quick_links_delete_own on public.user_quick_links for delete to authenticated using (user_id = auth.uid());

create function public.replace_own_quick_links(p_links jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  if auth.uid() is null or public.current_app_role() <> 'OWNER' then raise exception 'Forbidden'; end if;
  if not public.current_organization_is_active() or not public.current_organization_setup_completed() then raise exception 'Organization unavailable'; end if;
  if jsonb_typeof(p_links) <> 'array' or jsonb_array_length(p_links) > 7 then raise exception 'Invalid quick links'; end if;
  select count(distinct upper(item ->> 'service')) into v_count from jsonb_array_elements(p_links) item;
  if v_count <> jsonb_array_length(p_links) then raise exception 'Duplicate quick link service'; end if;

  delete from public.user_quick_links where user_id = auth.uid();
  insert into public.user_quick_links (user_id, service, url, enabled)
  select auth.uid(), upper(item ->> 'service'), item ->> 'url', coalesce((item ->> 'enabled')::boolean, true)
  from jsonb_array_elements(p_links) item;
end;
$$;

revoke all on function public.quick_link_url_allowed(text, text) from public, anon;
revoke all on function public.replace_own_quick_links(jsonb) from public, anon;
grant execute on function public.replace_own_quick_links(jsonb) to authenticated;
grant execute on function public.quick_link_url_allowed(text, text) to authenticated;

comment on table public.user_quick_links is 'Enlaces personales configurables; cada identidad accede exclusivamente a sus propios registros.';
