-- Ciclo reversible de baja para organizaciones y cuentas CUSTOMER.
-- Conserva los registros históricos y separa la solicitud del borrado de Auth.

create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  subject_type text not null check (subject_type in ('ORGANIZATION', 'CUSTOMER_ACCOUNT')),
  organization_id uuid references public.organizations(id) on delete restrict,
  target_user_id uuid references auth.users(id) on delete set null,
  requested_by uuid references auth.users(id) on delete set null,
  reason text not null check (char_length(trim(reason)) between 3 and 300),
  status text not null default 'PENDING' check (status in ('PENDING', 'CANCELLED', 'COMPLETED')),
  requested_at timestamptz not null default now(),
  scheduled_for timestamptz not null default (now() + interval '30 days'),
  cancelled_at timestamptz,
  completed_at timestamptz,
  auth_cleanup_completed boolean not null default false,
  constraint account_deletion_subject_check check (
    (subject_type = 'ORGANIZATION' and organization_id is not null)
    or (subject_type = 'CUSTOMER_ACCOUNT' and target_user_id is not null)
  )
);

create unique index account_deletion_pending_organization_unique
  on public.account_deletion_requests (organization_id)
  where subject_type = 'ORGANIZATION' and status = 'PENDING';
create unique index account_deletion_pending_user_unique
  on public.account_deletion_requests (target_user_id)
  where subject_type = 'CUSTOMER_ACCOUNT' and status = 'PENDING';
create index account_deletion_due_idx
  on public.account_deletion_requests (scheduled_for)
  where status = 'PENDING';

alter table public.customers
  add column if not exists portal_account_deleted_at timestamptz;

-- Eliminar una identidad de Auth no debe borrar ni bloquear el histórico técnico.
alter table public.customer_devices alter column created_by drop not null;
alter table public.customer_devices drop constraint if exists customer_devices_created_by_fkey;
alter table public.customer_devices add constraint customer_devices_created_by_fkey foreign key (created_by) references auth.users(id) on delete set null;
alter table public.device_receptions alter column created_by drop not null;
alter table public.device_receptions drop constraint if exists device_receptions_created_by_fkey;
alter table public.device_receptions add constraint device_receptions_created_by_fkey foreign key (created_by) references auth.users(id) on delete set null;
alter table public.reception_photos alter column uploaded_by drop not null;
alter table public.reception_photos drop constraint if exists reception_photos_uploaded_by_fkey;
alter table public.reception_photos add constraint reception_photos_uploaded_by_fkey foreign key (uploaded_by) references auth.users(id) on delete set null;

-- Un rol deja de ser utilizable si su perfil o su organización no están activos.
-- Las RPC de reactivación leen el perfil directamente y no dependen de esta función.
create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  left join public.organizations o on o.id = p.organization_id
  where p.id = auth.uid()
    and p.status = 'ACTIVE'
    and (p.role = 'SUPERADMIN' or (o.id is not null and o.status = 'ACTIVE'))
$$;

create or replace function public.request_organization_deletion(p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_organization public.organizations%rowtype;
  v_reason text := regexp_replace(trim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_open_receptions integer;
  v_request_id uuid;
  v_scheduled_for timestamptz := now() + interval '30 days';
begin
  select * into v_profile from public.profiles where id = auth.uid() for update;
  if not found or v_profile.role <> 'OWNER' or v_profile.status <> 'ACTIVE' or v_profile.organization_id is null then
    raise exception 'FORBIDDEN';
  end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'INVALID_REASON'; end if;

  select * into v_organization from public.organizations where id = v_profile.organization_id for update;
  if not found or v_organization.status <> 'ACTIVE' then raise exception 'ORGANIZATION_UNAVAILABLE'; end if;

  select count(*) into v_open_receptions
  from public.device_receptions
  where organization_id = v_organization.id and status = 'CONFIRMED';

  if v_open_receptions > 0 then
    return jsonb_build_object(
      'ok', false,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'OPEN_RECEPTIONS',
        'count', v_open_receptions,
        'message', format('Hay %s reparacion(es) o equipo(s) pendientes de resolución/retiro.', v_open_receptions)
      ))
    );
  end if;

  insert into public.account_deletion_requests
    (subject_type, organization_id, requested_by, reason, scheduled_for)
  values ('ORGANIZATION', v_organization.id, auth.uid(), v_reason, v_scheduled_for)
  returning id into v_request_id;

  update public.organizations set status = 'SUSPENDED' where id = v_organization.id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization.id, auth.uid(), 'ORGANIZATION_DELETION_REQUESTED', 'ORGANIZATION', v_organization.id,
    jsonb_build_object('request_id', v_request_id, 'reason', v_reason, 'status', 'PENDING', 'scheduled_for', v_scheduled_for));

  return jsonb_build_object('ok', true, 'requestId', v_request_id, 'scheduledFor', v_scheduled_for);
end;
$$;

create or replace function public.request_customer_account_deletion(p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_reason text := regexp_replace(trim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_open_receptions integer;
  v_request_id uuid;
  v_scheduled_for timestamptz := now() + interval '30 days';
begin
  select * into v_profile from public.profiles where id = auth.uid() for update;
  if not found or v_profile.role <> 'CUSTOMER' or v_profile.status <> 'ACTIVE' then raise exception 'FORBIDDEN'; end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'INVALID_REASON'; end if;

  select count(*) into v_open_receptions
  from public.device_receptions r
  join public.customer_user_links l
    on l.customer_id = r.customer_id and l.organization_id = r.organization_id
  where l.auth_user_id = auth.uid() and r.status = 'CONFIRMED';

  if v_open_receptions > 0 then
    return jsonb_build_object(
      'ok', false,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'OPEN_RECEPTIONS',
        'count', v_open_receptions,
        'message', format('Tenés %s reparacion(es) o equipo(s) pendientes de resolución/retiro.', v_open_receptions)
      ))
    );
  end if;

  insert into public.account_deletion_requests
    (subject_type, organization_id, target_user_id, requested_by, reason, scheduled_for)
  values ('CUSTOMER_ACCOUNT', v_profile.organization_id, auth.uid(), auth.uid(), v_reason, v_scheduled_for)
  returning id into v_request_id;

  update public.profiles set status = 'SUSPENDED' where id = auth.uid();
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_profile.organization_id, auth.uid(), 'CUSTOMER_ACCOUNT_DELETION_REQUESTED', 'PROFILE', auth.uid(),
    jsonb_build_object('request_id', v_request_id, 'reason', v_reason, 'status', 'PENDING', 'scheduled_for', v_scheduled_for));

  return jsonb_build_object('ok', true, 'requestId', v_request_id, 'scheduledFor', v_scheduled_for);
end;
$$;

create or replace function public.get_my_pending_deletion()
returns table (id uuid, subject_type text, organization_id uuid, reason text, requested_at timestamptz, scheduled_for timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.subject_type, r.organization_id, r.reason, r.requested_at, r.scheduled_for
  from public.account_deletion_requests r
  where r.status = 'PENDING'
    and (
      r.target_user_id = auth.uid()
      or r.requested_by = auth.uid()
      or (r.subject_type='ORGANIZATION' and exists (
        select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=r.organization_id
      ))
    )
  order by r.requested_at desc
  limit 1
$$;

create or replace function public.cancel_my_pending_deletion()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.account_deletion_requests%rowtype;
begin
  select * into v_request
  from public.account_deletion_requests
  where status = 'PENDING' and (
    target_user_id = auth.uid()
    or requested_by = auth.uid()
    or (subject_type='ORGANIZATION' and exists (
      select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=account_deletion_requests.organization_id
    ))
  )
  order by requested_at desc limit 1 for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if v_request.scheduled_for <= now() then raise exception 'RECOVERY_PERIOD_EXPIRED'; end if;

  if v_request.subject_type = 'ORGANIZATION' then
    update public.organizations set status = 'ACTIVE' where id = v_request.organization_id and status = 'SUSPENDED';
  else
    update public.profiles set status = 'ACTIVE' where id = auth.uid() and status = 'SUSPENDED';
  end if;
  update public.account_deletion_requests set status = 'CANCELLED', cancelled_at = now() where id = v_request.id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_request.organization_id, auth.uid(), v_request.subject_type || '_DELETION_CANCELLED', v_request.subject_type,
    coalesce(v_request.organization_id, auth.uid()), jsonb_build_object('request_id', v_request.id, 'status', 'CANCELLED'));
  return jsonb_build_object('ok', true, 'subjectType', v_request.subject_type);
end;
$$;

-- Primera fase del purgado: conserva organizaciones, clientes, recepciones y auditoría,
-- pero inutiliza identidades y borra preferencias personales eliminables.
create or replace function public.finalize_due_account_deletions()
returns table (request_id uuid, subject_type text, organization_id uuid, target_user_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.account_deletion_requests%rowtype;
  v_open integer;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then raise exception 'FORBIDDEN'; end if;
  for v_request in
    select * from public.account_deletion_requests where status = 'PENDING' and scheduled_for <= now() order by scheduled_for for update skip locked
  loop
    if v_request.subject_type = 'ORGANIZATION' then
      select count(*) into v_open from public.device_receptions where organization_id = v_request.organization_id and status = 'CONFIRMED';
    else
      select count(*) into v_open from public.device_receptions r join public.customer_user_links l on l.customer_id=r.customer_id and l.organization_id=r.organization_id
      where l.auth_user_id=v_request.target_user_id and r.status='CONFIRMED';
    end if;
    if v_open > 0 then continue; end if;

    if v_request.subject_type = 'CUSTOMER_ACCOUNT' then
      update public.customers c set portal_account_deleted_at = now()
      where exists (select 1 from public.customer_user_links l where l.customer_id=c.id and l.organization_id=c.organization_id and l.auth_user_id=v_request.target_user_id);
      delete from public.customer_user_links where auth_user_id=v_request.target_user_id;
      delete from public.user_quick_links where user_id=v_request.target_user_id;
      update public.profiles set first_name=null,last_name=null,display_name='Cuenta eliminada',status='DISABLED' where id=v_request.target_user_id;
    else
      delete from public.user_quick_links where user_id in (select id from public.profiles where organization_id=v_request.organization_id);
      update public.profiles set first_name=null,last_name=null,display_name='Cuenta eliminada',status='DISABLED' where organization_id=v_request.organization_id;
    end if;

    update public.account_deletion_requests set status='COMPLETED',completed_at=now() where id=v_request.id;
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_request.organization_id, null, v_request.subject_type || '_DELETION_COMPLETED', v_request.subject_type,
      coalesce(v_request.organization_id, v_request.target_user_id), jsonb_build_object('request_id',v_request.id,'status','COMPLETED'));
    request_id:=v_request.id; subject_type:=v_request.subject_type; organization_id:=v_request.organization_id; target_user_id:=v_request.target_user_id;
    return next;
  end loop;
end;
$$;

create or replace function public.mark_deletion_auth_cleanup(p_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if current_user not in ('postgres','service_role','supabase_admin') then raise exception 'FORBIDDEN'; end if;
  update public.account_deletion_requests set auth_cleanup_completed=true where id=p_request_id and status='COMPLETED';
end; $$;

alter table public.account_deletion_requests enable row level security;
create policy account_deletion_requests_self_select on public.account_deletion_requests
  for select to authenticated using (
    target_user_id=auth.uid()
    or requested_by=auth.uid()
    or public.current_app_role()='SUPERADMIN'
    or (subject_type='ORGANIZATION' and exists (
      select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=account_deletion_requests.organization_id
    ))
  );

revoke all on table public.account_deletion_requests from anon, authenticated;
grant select on public.account_deletion_requests to authenticated;
revoke all on function public.request_organization_deletion(text) from public, anon;
revoke all on function public.request_customer_account_deletion(text) from public, anon;
revoke all on function public.get_my_pending_deletion() from public, anon;
revoke all on function public.cancel_my_pending_deletion() from public, anon;
revoke all on function public.finalize_due_account_deletions() from public, anon, authenticated;
revoke all on function public.mark_deletion_auth_cleanup(uuid) from public, anon, authenticated;
grant execute on function public.request_organization_deletion(text) to authenticated;
grant execute on function public.request_customer_account_deletion(text) to authenticated;
grant execute on function public.get_my_pending_deletion() to authenticated;
grant execute on function public.cancel_my_pending_deletion() to authenticated;
grant execute on function public.finalize_due_account_deletions() to service_role;
grant execute on function public.mark_deletion_auth_cleanup(uuid) to service_role;

comment on table public.account_deletion_requests is 'Solicitudes append-like de baja reversible; el histórico legal permanece en las tablas de negocio y auditoría.';
