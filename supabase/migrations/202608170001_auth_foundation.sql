-- Nodo · base multiempresa, autenticación, autorización, auditoría y rate limiting.
create extension if not exists pgcrypto;

create type public.app_role as enum ('SUPERADMIN', 'OWNER', 'CUSTOMER', 'TECHNICIAN');
create type public.profile_status as enum ('ACTIVE', 'SUSPENDED', 'DISABLED');
create type public.organization_status as enum ('ACTIVE', 'SUSPENDED');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  status public.organization_status not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete restrict,
  first_name text,
  last_name text,
  display_name text,
  role public.app_role not null default 'CUSTOMER',
  status public.profile_status not null default 'ACTIVE',
  must_change_password boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_names_length check (
    (first_name is null or char_length(first_name) <= 80)
    and (last_name is null or char_length(last_name) <= 80)
    and (display_name is null or char_length(display_name) <= 170)
  )
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  first_name text not null check (char_length(first_name) between 1 and 80),
  last_name text not null check (char_length(last_name) between 1 and 80),
  contact_email text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.customer_user_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid not null,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (customer_id, auth_user_id),
  foreign key (customer_id, organization_id) references public.customers(id, organization_id) on delete cascade
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (char_length(event_type) between 3 and 100),
  entity_type text not null check (char_length(entity_type) between 2 and 80),
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.auth_rate_limits (
  action text not null,
  key_hash text not null check (char_length(key_hash) = 64),
  attempts integer not null default 0 check (attempts >= 0),
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (action, key_hash)
);

create index profiles_organization_idx on public.profiles (organization_id);
create index customers_organization_idx on public.customers (organization_id);
create index customer_user_links_user_idx on public.customer_user_links (auth_user_id);
create index customer_user_links_organization_idx on public.customer_user_links (organization_id);
create index audit_events_organization_created_idx on public.audit_events (organization_id, created_at desc);
create index audit_events_actor_created_idx on public.audit_events (actor_user_id, created_at desc);
create index auth_rate_limits_updated_idx on public.auth_rate_limits (updated_at);

create function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_set_updated_at before update on public.organizations for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger customers_set_updated_at before update on public.customers for each row execute function public.set_updated_at();

create function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$ select role from public.profiles where id = auth.uid() $$;

create function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select organization_id from public.profiles where id = auth.uid() $$;

create function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_first_name text := left(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 80);
  v_last_name text := left(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), 80);
begin
  insert into public.profiles (id, first_name, last_name, display_name, role)
  values (new.id, v_first_name, v_last_name, nullif(concat_ws(' ', v_first_name, v_last_name), ''), 'CUSTOMER')
  on conflict (id) do nothing;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (new.id, 'AUTH_ACCOUNT_CREATED', 'PROFILE', new.id, jsonb_build_object('provider', coalesce(new.raw_app_meta_data ->> 'provider', 'email')));
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();

create function public.prevent_profile_privilege_escalation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
    and auth.uid() = old.id
    and (
      new.role is distinct from old.role
      or new.organization_id is distinct from old.organization_id
      or new.status is distinct from old.status
      or new.must_change_password is distinct from old.must_change_password
    )
  then
    raise exception 'Privileged profile fields require an authorized server function';
  end if;
  return new;
end;
$$;

create trigger profiles_prevent_privilege_escalation before update on public.profiles for each row execute function public.prevent_profile_privilege_escalation();

create function public.log_audit_event(
  p_event_type text,
  p_entity_type text,
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_metadata::text ~* '(password|token|secret|cookie)' then
    raise exception 'Sensitive metadata keys are not allowed';
  end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (public.current_organization_id(), auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;

create function public.complete_password_change()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set must_change_password = false where id = auth.uid();
end;
$$;

create function public.admin_update_profile_access(
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
  select * into v_old from public.profiles where id = p_user_id for update;
  if not found then raise exception 'Profile not found'; end if;

  if v_old.role = 'SUPERADMIN' and v_old.status = 'ACTIVE' and (p_role <> 'SUPERADMIN' or p_status <> 'ACTIVE') then
    select count(*) into v_active_superadmins from public.profiles where role = 'SUPERADMIN' and status = 'ACTIVE';
    if v_active_superadmins <= 1 then raise exception 'Cannot disable the last active superadmin'; end if;
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
  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'ADMIN_PROFILE_ACCESS_UPDATED', 'PROFILE', p_user_id, jsonb_build_object('old_role', v_old.role, 'new_role', p_role, 'old_status', v_old.status, 'new_status', p_status));
end;
$$;

create function public.admin_create_organization(name text, slug text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  insert into public.organizations (name, slug) values (trim(name), lower(trim(slug))) returning id into v_id;
  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'ADMIN_ORGANIZATION_CREATED', 'ORGANIZATION', v_id, '{}'::jsonb);
  return v_id;
end;
$$;

create function public.consume_auth_rate_limit(p_action text, p_key_hash text)
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
    else raise exception 'Unsupported rate-limit action';
  end case;
  if p_key_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid key hash'; end if;

  insert into public.auth_rate_limits (action, key_hash, attempts, window_started_at, updated_at)
  values (upper(p_action), p_key_hash, 0, v_now, v_now)
  on conflict do nothing;
  select * into v_row from public.auth_rate_limits where action = upper(p_action) and key_hash = p_key_hash for update;

  if v_row.blocked_until is not null and v_row.blocked_until > v_now then
    return query select false, greatest(1, ceil(extract(epoch from (v_row.blocked_until - v_now)))::integer);
    return;
  end if;

  if v_row.window_started_at + v_window <= v_now then
    update public.auth_rate_limits set attempts = 1, window_started_at = v_now, blocked_until = null, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
    return query select true, 0;
    return;
  end if;

  if v_row.attempts >= v_max then
    update public.auth_rate_limits set blocked_until = v_now + v_block, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
    return query select false, ceil(extract(epoch from v_block))::integer;
    return;
  end if;

  update public.auth_rate_limits set attempts = attempts + 1, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
  return query select true, 0;
end;
$$;

create function public.reset_auth_rate_limit(p_action text, p_key_hash text)
returns void
language sql
security definer
set search_path = ''
as $$ delete from public.auth_rate_limits where action = upper(p_action) and key_hash = p_key_hash $$;

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.customer_user_links enable row level security;
alter table public.audit_events enable row level security;
alter table public.auth_rate_limits enable row level security;

grant select on public.organizations, public.profiles, public.customers, public.customer_user_links, public.audit_events to authenticated;
grant update on public.profiles to authenticated;
grant insert, update on public.customers to authenticated;
grant insert, delete on public.customer_user_links to authenticated;

create policy organizations_select on public.organizations for select to authenticated using (id = public.current_organization_id() or public.current_app_role() = 'SUPERADMIN');
create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or public.current_app_role() = 'SUPERADMIN' or (public.current_app_role() = 'OWNER' and organization_id = public.current_organization_id()));
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy customers_select on public.customers for select to authenticated using (organization_id = public.current_organization_id() and (public.current_app_role() = 'OWNER' or exists (select 1 from public.customer_user_links l where l.customer_id = customers.id and l.auth_user_id = auth.uid())) or public.current_app_role() = 'SUPERADMIN');
create policy customers_insert on public.customers for insert to authenticated with check (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER');
create policy customers_update on public.customers for update to authenticated using (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER') with check (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER');
create policy customer_links_select on public.customer_user_links for select to authenticated using (auth_user_id = auth.uid() or (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER') or public.current_app_role() = 'SUPERADMIN');
create policy customer_links_insert on public.customer_user_links for insert to authenticated with check (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER' and created_by = auth.uid());
create policy customer_links_delete on public.customer_user_links for delete to authenticated using (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER');
create policy audit_events_select on public.audit_events for select to authenticated using (public.current_app_role() = 'SUPERADMIN' or (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER'));

revoke all on table public.auth_rate_limits from anon, authenticated;
revoke insert, update, delete on table public.audit_events from anon, authenticated;
revoke all on function public.log_audit_event(text, text, uuid, jsonb) from public, anon;
revoke all on function public.complete_password_change() from public, anon;
revoke all on function public.admin_update_profile_access(uuid, public.app_role, public.profile_status, uuid) from public, anon;
revoke all on function public.admin_create_organization(text, text) from public, anon;
revoke all on function public.consume_auth_rate_limit(text, text) from public, anon, authenticated;
revoke all on function public.reset_auth_rate_limit(text, text) from public, anon, authenticated;
grant execute on function public.admin_update_profile_access(uuid, public.app_role, public.profile_status, uuid) to authenticated;
grant execute on function public.admin_create_organization(text, text) to authenticated;
grant execute on function public.log_audit_event(text, text, uuid, jsonb) to authenticated;
grant execute on function public.complete_password_change() to authenticated;
grant execute on function public.consume_auth_rate_limit(text, text) to service_role;
grant execute on function public.reset_auth_rate_limit(text, text) to service_role;

comment on table public.customers is 'Datos de contacto del cliente; no equivale a una identidad de Auth.';
comment on table public.customer_user_links is 'Vínculo explícito y opcional entre un cliente del negocio y una identidad de Auth.';
comment on table public.auth_rate_limits is 'Contadores efímeros por HMAC; nunca almacena IP ni correo en claro.';
