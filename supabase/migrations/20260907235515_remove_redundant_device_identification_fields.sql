begin;

-- The upper identification block is the canonical UI.  Do not let stale
-- dynamic bindings render a second copy below it.
update public.device_type_fields binding
set is_active = false
from public.device_form_sections section
where binding.fk_seccion_formulario_dispositivo_id = section.id
  and section.key like '%_identification'
  and binding.fk_campo_dispositivo_id not in (
    select id from public.device_fields where key in ('color', 'color_id')
  );

update public.device_type_fields binding
set is_active = false
from public.device_fields field
where binding.fk_campo_dispositivo_id = field.id
  and field.key = 'service_tag';

update public.device_fields set is_active = false where key = 'service_tag';

-- Preserve the public RPC signature for deployed clients during rollout. The
-- observation column is retained because it already exists on the remote
-- canonical table and may contain historical data; reception observations
-- remain owned by device_receptions.
create or replace function public.save_customer_device_identification(
  p_customer_id uuid,p_device_type_id uuid,p_device_brand_id uuid,p_device_model_id uuid,
  p_serial_number text default null,p_observations text default null,p_customer_device_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin
  if not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  if not exists(select 1 from public.device_types where id=p_device_type_id and is_active) then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if not exists(select 1 from public.device_type_brands r join public.device_brands b on b.id=r.fk_marca_dispositivo_id where r.fk_tipo_dispositivo_id=p_device_type_id and r.fk_marca_dispositivo_id=p_device_brand_id and b.is_active and (b.alcance='GLOBAL' or b.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if not exists(select 1 from public.device_models m where m.id=p_device_model_id and m.fk_tipo_dispositivo_id=p_device_type_id and m.fk_marca_dispositivo_id=p_device_brand_id and m.is_active and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if char_length(coalesce(p_serial_number,''))>120 then raise exception 'INVALID_DEVICE_DATA'; end if;
  if p_customer_device_id is null then
    insert into public.customer_devices(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,numero_serie,created_by)
    values(v_org,p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,nullif(btrim(p_serial_number),''),auth.uid()) returning id into v_id;
  else
    update public.customer_devices set fk_tipo_dispositivo_id=p_device_type_id,fk_marca_dispositivo_id=p_device_brand_id,fk_modelo_dispositivo_id=p_device_model_id,numero_serie=nullif(btrim(p_serial_number),''),updated_at=now()
    where id=p_customer_device_id and fk_cliente_id=p_customer_id and fk_organizacion_id=v_org returning id into v_id;
    if v_id is null then raise exception 'INVALID_DEVICE'; end if;
  end if;
  return v_id;
end $$;

commit;
