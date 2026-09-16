-- Defensa adicional: una cuenta CUSTOMER no puede iniciar su baja desde una organización suspendida.
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
  if v_profile.organization_id is not null and not exists (
    select 1 from public.organizations where id=v_profile.organization_id and status='ACTIVE'
  ) then raise exception 'ORGANIZATION_UNAVAILABLE'; end if;
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

revoke all on function public.request_customer_account_deletion(text) from public, anon;
grant execute on function public.request_customer_account_deletion(text) to authenticated;
