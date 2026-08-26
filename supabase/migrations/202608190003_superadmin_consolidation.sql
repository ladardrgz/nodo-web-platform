-- Consolidación SUPERADMIN: auditoría, suspensión real e invariante de acceso global.
alter table public.audit_events
  add column if not exists result text not null default 'SUCCESS';

alter table public.audit_events drop constraint if exists audit_events_result_check;
alter table public.audit_events
  add constraint audit_events_result_check check (result in ('SUCCESS', 'FAILURE'));

create index if not exists audit_events_type_created_idx on public.audit_events (event_type, created_at desc);
create index if not exists audit_events_result_created_idx on public.audit_events (result, created_at desc);
create index if not exists audit_events_created_idx on public.audit_events (created_at desc);

create or replace function public.consume_auth_rate_limit(p_action text, p_key_hash text)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_max integer;
  v_window interval;
  v_block interval;
  v_row public.auth_rate_limits%rowtype;
begin
  case upper(p_action)
    when 'LOGIN' then v_max := 5; v_window := interval '15 minutes'; v_block := interval '15 minutes';
    when 'REGISTER' then v_max := 3; v_window := interval '1 hour'; v_block := interval '1 hour';
    when 'PASSWORD_RESET' then v_max := 3; v_window := interval '1 hour'; v_block := interval '1 hour';
    when 'RESEND_VERIFICATION' then v_max := 3; v_window := interval '1 hour'; v_block := interval '1 hour';
    when 'OAUTH' then v_max := 20; v_window := interval '15 minutes'; v_block := interval '15 minutes';
    when 'ADMIN_MUTATION' then v_max := 60; v_window := interval '15 minutes'; v_block := interval '15 minutes';
    else raise exception 'Unsupported rate-limit action';
  end case;
  if p_key_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid key hash'; end if;
  insert into public.auth_rate_limits (action, key_hash, attempts, window_started_at, updated_at)
  values (upper(p_action), p_key_hash, 0, v_now, v_now) on conflict do nothing;
  select * into v_row from public.auth_rate_limits where action = upper(p_action) and key_hash = p_key_hash for update;
  if v_row.blocked_until is not null and v_row.blocked_until > v_now then
    return query select false, greatest(1, ceil(extract(epoch from (v_row.blocked_until - v_now)))::integer); return;
  end if;
  if v_row.window_started_at + v_window <= v_now then
    update public.auth_rate_limits set attempts = 1, window_started_at = v_now, blocked_until = null, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
    return query select true, 0; return;
  end if;
  if v_row.attempts >= v_max then
    update public.auth_rate_limits set blocked_until = v_now + v_block, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
    return query select false, ceil(extract(epoch from v_block))::integer; return;
  end if;
  update public.auth_rate_limits set attempts = attempts + 1, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
  return query select true, 0;
end;
$$;

create or replace function public.log_audit_event(
  p_event_type text,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (public.current_organization_id(), auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.current_organization_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select status = 'ACTIVE' from public.organizations where id = public.current_organization_id()), false)
$$;

-- El bloqueo operativo se refuerza en RLS; SUPERADMIN conserva inspección global.
drop policy if exists customers_select on public.customers;
drop policy if exists customers_insert on public.customers;
drop policy if exists customers_update on public.customers;
drop policy if exists customer_links_select on public.customer_user_links;
drop policy if exists customer_links_insert on public.customer_user_links;
drop policy if exists customer_links_delete on public.customer_user_links;

create policy customers_select on public.customers for select to authenticated using (
  public.current_app_role() = 'SUPERADMIN'
  or (
    organization_id = public.current_organization_id()
    and public.current_organization_is_active()
    and public.current_organization_setup_completed()
    and (
      public.current_app_role() = 'OWNER'
      or exists (select 1 from public.customer_user_links l where l.customer_id = customers.id and l.auth_user_id = auth.uid())
    )
  )
);
create policy customers_insert on public.customers for insert to authenticated with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and public.current_organization_setup_completed()
);
create policy customers_update on public.customers for update to authenticated using (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and public.current_organization_setup_completed()
) with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and public.current_organization_setup_completed()
);
create policy customer_links_select on public.customer_user_links for select to authenticated using (
  public.current_app_role() = 'SUPERADMIN'
  or (
    public.current_organization_is_active()
    and (
      auth_user_id = auth.uid()
      or (
        organization_id = public.current_organization_id()
        and public.current_app_role() = 'OWNER'
        and public.current_organization_setup_completed()
      )
    )
  )
);
create policy customer_links_insert on public.customer_user_links for insert to authenticated with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and public.current_organization_setup_completed()
  and created_by = auth.uid()
);
create policy customer_links_delete on public.customer_user_links for delete to authenticated using (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and public.current_organization_setup_completed()
);

drop policy if exists organization_logos_select on storage.objects;
drop policy if exists organization_logos_insert on storage.objects;
drop policy if exists organization_logos_update on storage.objects;
drop policy if exists organization_logos_delete on storage.objects;
create policy organization_logos_select on storage.objects for select to authenticated using (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);
create policy organization_logos_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);
create policy organization_logos_update on storage.objects for update to authenticated using (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and (storage.foldername(name))[1] = public.current_organization_id()::text
) with check (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);
create policy organization_logos_delete on storage.objects for delete to authenticated using (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and public.current_organization_is_active()
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create or replace function public.admin_create_organization(name text, slug text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text := regexp_replace(trim(name), '[[:space:]]+', ' ', 'g');
  v_slug text := lower(trim(slug));
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if char_length(v_name) not between 2 and 120 or v_name !~ '^[[:alnum:]_ -]+$' then raise exception 'Invalid organization name'; end if;
  if char_length(v_slug) not between 2 and 80 or v_slug !~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$' then raise exception 'Invalid organization identifier'; end if;
  insert into public.organizations (name, slug) values (v_name, v_slug) returning id into v_id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_id, auth.uid(), 'ORGANIZATION_CREATED', 'ORGANIZATION', v_id, jsonb_build_object('after', jsonb_build_object('name', v_name, 'slug', v_slug, 'status', 'ACTIVE')));
  return v_id;
end;
$$;

create function public.update_own_superadmin_profile(p_first_name text, p_last_name text, p_display_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_first_name text := regexp_replace(trim(p_first_name), '[[:space:]]+', ' ', 'g');
  v_last_name text := regexp_replace(trim(p_last_name), '[[:space:]]+', ' ', 'g');
  v_display_name text := regexp_replace(trim(p_display_name), '[[:space:]]+', ' ', 'g');
begin
  if auth.uid() is null or public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if char_length(v_first_name) not between 2 and 80 or char_length(v_last_name) not between 2 and 80 or char_length(v_display_name) not between 2 and 170 then raise exception 'Invalid profile'; end if;
  update public.profiles set first_name = v_first_name, last_name = v_last_name, display_name = v_display_name where id = auth.uid();
  if not found then raise exception 'Profile not found'; end if;
end;
$$;

create function public.audit_profile_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.first_name is distinct from new.first_name or old.last_name is distinct from new.last_name or old.display_name is distinct from new.display_name then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (new.organization_id, auth.uid(), 'PROFILE_UPDATED', 'PROFILE', new.id, jsonb_build_object('personal_data', true));
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_audit_personal_data on public.profiles;
create trigger profiles_audit_personal_data after update on public.profiles for each row execute function public.audit_profile_data_change();

create or replace function public.admin_update_profile_access(
  p_user_id uuid,
  p_role public.app_role,
  p_status public.profile_status,
  p_organization_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.profiles%rowtype;
  v_active_superadmins integer;
  v_organization_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nodo_active_superadmin_invariant', 0));
  select * into v_old from public.profiles where id = p_user_id for update;
  if not found then raise exception 'Profile not found'; end if;

  if v_old.role = 'SUPERADMIN' and v_old.status = 'ACTIVE' and (p_role <> 'SUPERADMIN' or p_status <> 'ACTIVE') then
    select count(*) into v_active_superadmins from public.profiles where role = 'SUPERADMIN' and status = 'ACTIVE';
    if v_active_superadmins <= 1 then raise exception 'LAST_ACTIVE_SUPERADMIN'; end if;
  end if;

  if p_role = 'SUPERADMIN' then
    v_organization_id := null;
  else
    if p_organization_id is null then raise exception 'Organization required'; end if;
    perform 1 from public.organizations where id = p_organization_id;
    if not found then raise exception 'Organization not found'; end if;
    v_organization_id := p_organization_id;
  end if;

  update public.profiles set role = p_role, status = p_status, organization_id = v_organization_id where id = p_user_id;
  if v_old.role is distinct from p_role then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_organization_id, auth.uid(), 'USER_ROLE_CHANGED', 'PROFILE', p_user_id, jsonb_build_object('before', jsonb_build_object('role', v_old.role), 'after', jsonb_build_object('role', p_role)));
  end if;
  if v_old.status is distinct from p_status then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_organization_id, auth.uid(), 'USER_STATUS_CHANGED', 'PROFILE', p_user_id, jsonb_build_object('before', jsonb_build_object('status', v_old.status), 'after', jsonb_build_object('status', p_status)));
  end if;
end;
$$;

create function public.admin_set_organization_status(p_organization_id uuid, p_status public.organization_status, p_confirmation text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_old public.organizations%rowtype;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  select * into v_old from public.organizations where id = p_organization_id for update;
  if not found then raise exception 'Organization not found'; end if;
  if v_old.status = p_status then return; end if;
  if p_status = 'SUSPENDED' and p_confirmation <> 'SUSPENDER' then raise exception 'Invalid confirmation'; end if;
  update public.organizations set status = p_status where id = p_organization_id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), case when p_status = 'SUSPENDED' then 'ORGANIZATION_SUSPENDED' else 'ORGANIZATION_REACTIVATED' end, 'ORGANIZATION', p_organization_id, jsonb_build_object('before', jsonb_build_object('status', v_old.status), 'after', jsonb_build_object('status', p_status)));
end;
$$;

create function public.admin_log_organization_event(p_organization_id uuid, p_event_type text, p_entity_type text, p_entity_id uuid default null, p_metadata jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.admin_set_organization_status(uuid, public.organization_status, text) from public, anon;
revoke all on function public.admin_log_organization_event(uuid, text, text, uuid, jsonb) from public, anon;
revoke all on function public.update_own_superadmin_profile(text, text, text) from public, anon;
grant execute on function public.admin_set_organization_status(uuid, public.organization_status, text) to authenticated;
grant execute on function public.admin_log_organization_event(uuid, text, text, uuid, jsonb) to authenticated;
grant execute on function public.update_own_superadmin_profile(text, text, text) to authenticated;

comment on column public.audit_events.result is 'Resultado controlado del evento; nunca contiene detalles técnicos ni secretos.';
