-- Service orders: transactional business boundaries.  The caller's organization is
-- always derived from auth context; no RPC accepts an organization id from the UI.
create table if not exists public.service_order_number_counters (
  organization_id uuid primary key references public.organizations(id) on delete restrict,
  last_order_number bigint not null default 0 check (last_order_number >= 0),
  updated_at timestamptz not null default now()
);

alter table public.service_order_number_counters enable row level security;
revoke all on public.service_order_number_counters from anon, authenticated;

create or replace function public.assert_service_order_actor()
returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid; v_role public.app_role; v_status public.profile_status;
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  select p.organization_id, p.role, p.status into v_org, v_role, v_status
  from public.profiles p where p.id=auth.uid();
  if v_org is null or v_status <> 'ACTIVE' or v_role not in ('OWNER','TECHNICIAN') then
    raise exception 'SERVICE_ORDER_ACCESS_DENIED';
  end if;
  return v_org;
end $$;

create or replace function public.next_service_order_number(p_organization_id uuid)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_number bigint;
begin
  insert into public.service_order_number_counters(organization_id,last_order_number)
  values(p_organization_id,1)
  on conflict (organization_id) do update
    set last_order_number=public.service_order_number_counters.last_order_number+1,
        updated_at=now()
  returning last_order_number into v_number;
  return v_number;
end $$;

create or replace function public.create_service_order(p_reception_id uuid, p_priority_id uuid default null, p_complexity_id uuid default null, p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_service_order_actor(); v_order uuid; v_status uuid; v_number bigint;
begin
  if not exists(select 1 from public.device_receptions r where r.id=p_reception_id and r.fk_organizacion_id=v_org and r.status='CONFIRMADA') then
    raise exception 'INVALID_RECEPTION';
  end if;
  select id into v_order from public.service_orders where reception_id=p_reception_id;
  if v_order is not null then return v_order; end if;
  select id into v_status from public.service_order_statuses where code='OPEN' and is_active;
  if v_status is null then raise exception 'INITIAL_STATUS_NOT_CONFIGURED'; end if;
  if p_priority_id is not null and not exists(select 1 from public.service_order_priorities where id=p_priority_id and is_active and (organization_id is null or organization_id=v_org)) then raise exception 'INVALID_PRIORITY'; end if;
  if p_complexity_id is not null and not exists(select 1 from public.service_complexity_levels where id=p_complexity_id and is_active and (organization_id is null or organization_id=v_org)) then raise exception 'INVALID_COMPLEXITY'; end if;
  v_number:=public.next_service_order_number(v_org);
  insert into public.service_orders(organization_id,reception_id,order_number,status_id,priority_id,complexity_id,internal_notes,created_by)
  values(v_org,p_reception_id,v_number,v_status,p_priority_id,p_complexity_id,nullif(btrim(p_notes),''),auth.uid())
  returning id into v_order;
  insert into public.service_order_status_history(organization_id,service_order_id,status_id,changed_by,note)
  values(v_org,v_order,v_status,auth.uid(),'Orden abierta desde recepción confirmada');
  return v_order;
exception when unique_violation then
  select id into v_order from public.service_orders where reception_id=p_reception_id;
  if v_order is null then raise; end if;
  return v_order;
end $$;

create or replace function public.change_service_order_status(p_service_order_id uuid, p_status_code text, p_note text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_service_order_actor(); v_current text; v_next uuid; v_terminal boolean;
begin
  select s.code into v_current from public.service_orders o join public.service_order_statuses s on s.id=o.status_id where o.id=p_service_order_id and o.organization_id=v_org for update;
  if v_current is null then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if v_current in ('DELIVERED','CANCELLED') then raise exception 'TERMINAL_SERVICE_ORDER'; end if;
  select id,is_terminal into v_next,v_terminal from public.service_order_statuses where code=upper(btrim(p_status_code)) and is_active;
  if v_next is null then raise exception 'INVALID_SERVICE_ORDER_STATUS'; end if;
  if v_current='TECHNICALLY_COMPLETED' and upper(btrim(p_status_code)) not in ('READY','CANCELLED') then raise exception 'INVALID_STATUS_TRANSITION'; end if;
  if upper(btrim(p_status_code))='DELIVERED' and not exists(select 1 from public.service_order_deliveries where service_order_id=p_service_order_id and organization_id=v_org) then raise exception 'DELIVERY_RECORD_REQUIRED'; end if;
  update public.service_orders set status_id=v_next,technical_completed_at=case when upper(btrim(p_status_code))='TECHNICALLY_COMPLETED' then coalesce(technical_completed_at,now()) else technical_completed_at end,closed_at=case when v_terminal then coalesce(closed_at,now()) else closed_at end,updated_at=now() where id=p_service_order_id and organization_id=v_org;
  insert into public.service_order_status_history(organization_id,service_order_id,status_id,changed_by,note) values(v_org,p_service_order_id,v_next,auth.uid(),nullif(btrim(p_note),''));
end $$;

create or replace function public.assign_service_order_technician(p_service_order_id uuid, p_technician_user_id uuid, p_assignment_role text default 'TECHNICIAN', p_primary boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_service_order_actor(); v_id uuid;
begin
  if not exists(select 1 from public.service_orders where id=p_service_order_id and organization_id=v_org) then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if not exists(select 1 from public.profiles where id=p_technician_user_id and organization_id=v_org and role='TECHNICIAN' and status='ACTIVE') then raise exception 'TECHNICIAN_NOT_ACTIVE_IN_ORGANIZATION'; end if;
  if upper(btrim(p_assignment_role)) not in ('RECEPTION','DIAGNOSIS','TECHNICIAN','TESTING','LEAD') then raise exception 'INVALID_ASSIGNMENT_ROLE'; end if;
  select id into v_id from public.service_order_assignments where service_order_id=p_service_order_id and technician_user_id=p_technician_user_id and assignment_role=upper(btrim(p_assignment_role)) and unassigned_at is null;
  if v_id is null then insert into public.service_order_assignments(organization_id,service_order_id,technician_user_id,assignment_role,assigned_by) values(v_org,p_service_order_id,p_technician_user_id,upper(btrim(p_assignment_role)),auth.uid()) returning id into v_id; end if;
  if p_primary then update public.service_orders set primary_technician_id=p_technician_user_id,updated_at=now() where id=p_service_order_id and organization_id=v_org; end if;
  return v_id;
end $$;

create or replace function public.unassign_service_order_technician(p_assignment_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_service_order_actor(); v_order uuid; v_technician uuid;
begin
  update public.service_order_assignments set unassigned_at=now() where id=p_assignment_id and organization_id=v_org and unassigned_at is null returning service_order_id,technician_user_id into v_order,v_technician;
  if v_order is null then raise exception 'ACTIVE_ASSIGNMENT_NOT_FOUND'; end if;
  update public.service_orders set primary_technician_id=null,updated_at=now() where id=v_order and organization_id=v_org and primary_technician_id=v_technician;
end $$;

create or replace function public.record_service_order_time(p_service_order_id uuid,p_task_id uuid,p_started_at timestamptz,p_ended_at timestamptz default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_service_order_actor(); v_id uuid;
begin
  if p_started_at is null or (p_ended_at is not null and p_ended_at<p_started_at) then raise exception 'INVALID_TIME_RANGE'; end if;
  if not exists(select 1 from public.service_orders where id=p_service_order_id and organization_id=v_org) then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if p_task_id is not null and not exists(select 1 from public.service_order_tasks where id=p_task_id and service_order_id=p_service_order_id and organization_id=v_org) then raise exception 'INVALID_SERVICE_ORDER_TASK'; end if;
  insert into public.service_order_time_entries(organization_id,service_order_id,task_id,technician_user_id,started_at,ended_at,notes) values(v_org,p_service_order_id,p_task_id,auth.uid(),p_started_at,p_ended_at,nullif(btrim(p_notes),'')) returning id into v_id;
  return v_id;
end $$;

-- Trigger functions are invoked by PostgreSQL only; they must not be RPC endpoints.
revoke all on function public.validate_service_order_technician() from public, anon, authenticated;
revoke all on function public.assert_service_order_actor() from public, anon;
revoke all on function public.next_service_order_number(uuid) from public, anon, authenticated;
revoke all on function public.create_service_order(uuid,uuid,uuid,text) from public, anon;
revoke all on function public.change_service_order_status(uuid,text,text) from public, anon;
revoke all on function public.assign_service_order_technician(uuid,uuid,text,boolean) from public, anon;
revoke all on function public.unassign_service_order_technician(uuid) from public, anon;
revoke all on function public.record_service_order_time(uuid,uuid,timestamptz,timestamptz,text) from public, anon;
grant execute on function public.create_service_order(uuid,uuid,uuid,text),public.change_service_order_status(uuid,text,text),public.assign_service_order_technician(uuid,uuid,text,boolean),public.unassign_service_order_technician(uuid),public.record_service_order_time(uuid,uuid,timestamptz,timestamptz,text) to authenticated;
