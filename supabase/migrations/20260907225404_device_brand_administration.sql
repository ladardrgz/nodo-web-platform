-- A private brand can only be removed through this transaction.  The row lock
-- prevents a new historical device from being attached between the dependency
-- check and the delete.
create or replace function public.delete_private_device_brand(
  p_device_type_id uuid,
  p_device_brand_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.assert_reception_owner();
begin
  perform 1
  from public.device_brands b
  join public.device_type_brands r on r.fk_marca_dispositivo_id = b.id
  where b.id = p_device_brand_id
    and r.fk_tipo_dispositivo_id = p_device_type_id
    and b.fk_organizacion_id = v_org
  for update of b;

  if not found then
    raise exception 'DEVICE_BRAND_FORBIDDEN';
  end if;

  if exists (select 1 from public.customer_devices where fk_marca_dispositivo_id = p_device_brand_id)
    or exists (select 1 from public.device_models where fk_marca_dispositivo_id = p_device_brand_id) then
    raise exception 'DEVICE_BRAND_IN_USE';
  end if;

  delete from public.device_type_brands
  where fk_tipo_dispositivo_id = p_device_type_id
    and fk_marca_dispositivo_id = p_device_brand_id;

  delete from public.device_brands
  where id = p_device_brand_id
    and fk_organizacion_id = v_org;
end;
$$;

revoke all on function public.delete_private_device_brand(uuid, uuid) from public, anon;
grant execute on function public.delete_private_device_brand(uuid, uuid) to authenticated;
