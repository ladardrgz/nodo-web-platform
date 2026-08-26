-- Corrige la ambigüedad entre la columna de retorno status y profiles.status.
create or replace function public.finalize_initial_organization_setup()
returns table (status text, incomplete_section text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.current_organization_id();
  v_organization public.organizations%rowtype;
  v_address public.organization_addresses%rowtype;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or not exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'OWNER' and p.status = 'ACTIVE'
        and p.organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;

  select * into v_organization
  from public.organizations
  where id = v_organization_id
  for update;

  if not found then return query select 'UNAVAILABLE'::text, null::text; return; end if;
  if v_organization.status <> 'ACTIVE' then return query select 'SUSPENDED'::text, null::text; return; end if;
  if v_organization.initial_setup_completed then return query select 'ALREADY_COMPLETED'::text, null::text; return; end if;

  if char_length(trim(v_organization.name)) < 2
    or char_length(trim(coalesce(v_organization.trade_name, ''))) < 2 then
    return query select 'INCOMPLETE'::text, 'ORGANIZATION'::text; return;
  end if;
  if coalesce(trim(v_organization.phone), '') !~ '^\+[1-9][0-9]{7,14}$'
    or coalesce(trim(v_organization.contact_email), '') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return query select 'INCOMPLETE'::text, 'CONTACT'::text; return;
  end if;

  select * into v_address
  from public.organization_addresses
  where organization_id = v_organization_id;

  if not found
    or not exists (select 1 from public.countries where id = v_address.country_id and is_active)
    or not exists (select 1 from public.provinces where id = v_address.province_id and country_id = v_address.country_id and is_active)
    or not exists (select 1 from public.localities where id = v_address.locality_id and province_id = v_address.province_id and is_active)
    or (exists (select 1 from public.neighborhoods where locality_id = v_address.locality_id and is_active) and v_address.neighborhood_id is null)
    or (v_address.neighborhood_id is not null and not exists (
      select 1 from public.neighborhoods where id = v_address.neighborhood_id and locality_id = v_address.locality_id and is_active
    ))
    or char_length(trim(v_address.street)) < 2
    or (v_address.without_number and v_address.street_number is not null)
    or (not v_address.without_number and v_address.street_number is null) then
    return query select 'INCOMPLETE'::text, 'LOCATION'::text; return;
  end if;

  update public.organizations
  set initial_setup_completed = true,
      initial_setup_step = 4
  where id = v_organization_id;

  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, result, metadata
  ) values (
    v_organization_id, auth.uid(), 'INITIAL_SETUP_COMPLETED', 'ORGANIZATION', v_organization_id, 'SUCCESS', jsonb_build_object('final_step', 4)
  );

  return query select 'COMPLETED'::text, null::text;
end;
$$;

revoke all on function public.finalize_initial_organization_setup() from public, anon;
grant execute on function public.finalize_initial_organization_setup() to authenticated;

comment on function public.finalize_initial_organization_setup() is
  'Valida datos persistidos, completa el onboarding y registra auditoría en una única transacción idempotente.';
