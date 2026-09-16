begin;

-- La regla confirmada para Notebook exige CPU, al menos un módulo RAM,
-- al menos una unidad y sistema operativo. GPU, placa madre y pantalla siguen
-- siendo enriquecimiento opcional.
update public.device_type_fields binding
set required = true
from public.device_types dtype, public.device_fields field
where binding.fk_tipo_dispositivo_id = dtype.id
  and binding.fk_campo_dispositivo_id = field.id
  and dtype.code = 'notebook'
  and field.key in (
    'processor_brand_id','processor_family_id','processor_generation_id',
    'processor_model_id','ram_modules','storage_drives','operating_system_id'
  );

create or replace function public.save_customer_device_step_two(
  p_customer_id uuid,p_device_type_id uuid,p_device_brand_id uuid,p_device_model_id uuid,
  p_serial_number text default null,p_observations text default null,p_customer_device_id uuid default null,
  p_attributes jsonb default '{}'::jsonb,p_ram_modules jsonb default '[]'::jsonb,
  p_storage_drives jsonb default '[]'::jsonb,p_ports jsonb default '[]'::jsonb,p_accessory_ids uuid[] default '{}'::uuid[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_device_id uuid;
  v_item jsonb;
  v_device_type_code text;
  v_variant_id uuid := nullif(p_attributes->>'variant_id','')::uuid;
  v_color_id uuid := nullif(p_attributes->>'color_id','')::uuid;
  v_motherboard_model_id uuid := nullif(p_attributes->>'motherboard_model_id','')::uuid;
  v_cpu_brand_id uuid := nullif(p_attributes->>'processor_brand_id','')::uuid;
  v_cpu_family_id uuid := nullif(p_attributes->>'processor_family_id','')::uuid;
  v_cpu_generation_id uuid := nullif(p_attributes->>'processor_generation_id','')::uuid;
  v_cpu_model_id uuid := nullif(p_attributes->>'processor_model_id','')::uuid;
  v_gpu_brand_id uuid := nullif(p_attributes->>'gpu_brand_id','')::uuid;
  v_gpu_family_id uuid := nullif(p_attributes->>'gpu_family_id','')::uuid;
  v_gpu_model_id uuid := nullif(p_attributes->>'gpu_model_id','')::uuid;
begin
  perform public.assert_reception_owner();
  if jsonb_typeof(p_attributes)<>'object' or jsonb_typeof(p_ram_modules)<>'array' or jsonb_typeof(p_storage_drives)<>'array' or jsonb_typeof(p_ports)<>'array' then
    raise exception 'INVALID_DEVICE_DATA';
  end if;

  select code into v_device_type_code from public.device_types where id=p_device_type_id and is_active;
  if v_device_type_code is null then raise exception 'INVALID_DEVICE_TYPE'; end if;

  if v_variant_id is not null and not exists (
    select 1 from public.device_model_variants
    where id=v_variant_id and fk_modelo_dispositivo_id=p_device_model_id and is_active
  ) then raise exception 'INVALID_DEVICE_VARIANT'; end if;

  if v_color_id is not null and not exists (
    select 1 from public.device_colors
    where id=v_color_id and is_active
      and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id())
  ) then raise exception 'INVALID_DEVICE_COLOR'; end if;

  if v_motherboard_model_id is not null and not exists (
    select 1 from public.motherboard_models model
    join public.motherboard_model_device_types compatibility
      on compatibility.motherboard_model_id=model.id
    where model.id=v_motherboard_model_id and compatibility.device_type_id=p_device_type_id
      and model.is_active
      and (model.alcance='GLOBAL' or model.fk_organizacion_id=public.current_organization_id())
  ) then raise exception 'INVALID_MOTHERBOARD_COMPATIBILITY'; end if;

  if num_nonnulls(v_cpu_brand_id,v_cpu_family_id,v_cpu_generation_id,v_cpu_model_id) not in (0,4) then
    raise exception 'INCOMPLETE_PROCESSOR_SELECTION';
  end if;
  if v_cpu_model_id is not null and not exists (
    select 1 from public.processor_models model
    join public.processor_families family on family.id=model.fk_familia_procesador_id
    join public.processor_specifications specification on specification.fk_processor_model_id=model.id
    where model.id=v_cpu_model_id and model.activo
      and family.id=v_cpu_family_id and family.fk_marca_procesador_id=v_cpu_brand_id
      and model.fk_generacion_procesador_id=v_cpu_generation_id
      and ((v_device_type_code='notebook' and specification.notebook_supported)
        or (v_device_type_code='desktop_pc' and specification.desktop_supported))
  ) then raise exception 'INVALID_PROCESSOR_COMPATIBILITY'; end if;

  if num_nonnulls(v_gpu_brand_id,v_gpu_family_id,v_gpu_model_id) not in (0,3) then
    raise exception 'INCOMPLETE_GPU_SELECTION';
  end if;
  if v_gpu_model_id is not null and not exists (
    select 1 from public.gpu_models model
    join public.gpu_families family on family.id=model.fk_gpu_family_id
    where model.id=v_gpu_model_id and model.is_active and family.is_active
      and family.id=v_gpu_family_id and family.fk_gpu_brand_id=v_gpu_brand_id
      and ((v_device_type_code='notebook' and model.notebook_supported)
        or (v_device_type_code='desktop_pc' and model.desktop_supported))
  ) then raise exception 'INVALID_GPU_COMPATIBILITY'; end if;

  v_device_id:=public.save_customer_device_identification(p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,p_serial_number,p_observations,p_customer_device_id);

  update public.customer_devices
  set fk_variante_modelo_dispositivo_id=v_variant_id,
      fk_color_dispositivo_id=v_color_id,
      fk_motherboard_model_id=v_motherboard_model_id,
      updated_at=now()
  where id=v_device_id;

  delete from public.customer_device_ram_modules where fk_customer_device_id=v_device_id;
  for v_item in select value from jsonb_array_elements(p_ram_modules) loop
    insert into public.customer_device_ram_modules(fk_customer_device_id,fk_ram_type_id,fk_ram_speed_id,capacity_mb,fk_ram_form_factor_id,is_soldered,manufacturer,model)
    values(v_device_id,(v_item->>'type')::uuid,nullif(v_item->>'speedId','')::uuid,(v_item->>'capacity')::integer * 1024,nullif(v_item->>'formFactorId','')::uuid,coalesce((v_item->>'soldered')::boolean,false),nullif(btrim(v_item->>'manufacturer'),''),nullif(btrim(v_item->>'model'),''));
  end loop;
  delete from public.customer_device_ports where fk_customer_device_id=v_device_id;
  for v_item in select value from jsonb_array_elements(p_ports) loop
    insert into public.customer_device_ports(fk_customer_device_id,fk_port_connector_id,fk_port_protocol_id,quantity,condition)
    values(v_device_id,(v_item->>'connectorId')::uuid,nullif(v_item->>'protocolId','')::uuid,(v_item->>'quantity')::integer,nullif(v_item->>'condition',''));
  end loop;
  delete from public.customer_device_storage_drives where fk_customer_device_id=v_device_id;
  for v_item in select value from jsonb_array_elements(p_storage_drives) loop
    insert into public.customer_device_storage_drives(fk_customer_device_id,fk_storage_type_id,fk_storage_interface_id,fk_storage_form_factor_id,fk_storage_capacity_id,capacity_gb,manufacturer,model,serial_number,condition)
    values(v_device_id,nullif(v_item->>'type','')::uuid,nullif(v_item->>'interfaceId','')::uuid,nullif(v_item->>'formFactorId','')::uuid,nullif(v_item->>'capacity','')::uuid,
      (select capacity_gb from public.storage_capacities where id=nullif(v_item->>'capacity','')::uuid),nullif(btrim(v_item->>'manufacturer'),''),nullif(btrim(v_item->>'model'),''),nullif(btrim(v_item->>'serialNumber'),''),nullif(btrim(v_item->>'condition'),''));
  end loop;
  delete from public.customer_device_accessories where fk_dispositivo_cliente_id=v_device_id;
  insert into public.customer_device_accessories(fk_dispositivo_cliente_id,fk_accesorio_dispositivo_id,cantidad)
  select v_device_id,id,1 from unnest(coalesce(p_accessory_ids,'{}'::uuid[])) id;
  delete from public.customer_device_field_values where fk_dispositivo_cliente_id=v_device_id;
  insert into public.customer_device_field_values(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,valor_texto)
  select v_device_id,b.id,nullif(entry.value,'')
  from jsonb_each_text(p_attributes) entry
  join public.device_fields f on f.key=entry.key and f.is_active
  join public.device_type_fields b on b.fk_campo_dispositivo_id=f.id and b.fk_tipo_dispositivo_id=p_device_type_id and b.is_active
  where entry.value<>'';
  delete from public.customer_device_connectivity where fk_customer_device_id=v_device_id;
  insert into public.customer_device_connectivity(fk_customer_device_id,fk_connectivity_id)
  select v_device_id,value::uuid from jsonb_array_elements_text(coalesce(nullif(p_attributes->>'connectivity','')::jsonb,'[]'::jsonb));
  insert into public.customer_device_hardware_profiles(fk_customer_device_id,fk_processor_model_id,gpu_brand_id,gpu_family_id,gpu_model_id,fk_display_size_id,fk_display_resolution_id,fk_display_technology_id,fk_display_refresh_rate_id,display_touch,battery_present,battery_functional_status,charger_delivered,charger_condition,updated_at)
  values(v_device_id,v_cpu_model_id,v_gpu_brand_id,v_gpu_family_id,v_gpu_model_id,
    nullif(p_attributes->>'screen_size','')::uuid,nullif(p_attributes->>'screen_resolution','')::uuid,nullif(p_attributes->>'screen_technology','')::uuid,nullif(p_attributes->>'screen_refresh_rate','')::uuid,coalesce((p_attributes->>'screen_touch')::boolean,false),
    coalesce((p_attributes->>'battery_present')::boolean,false),nullif(p_attributes->>'battery_status',''),coalesce((p_attributes->>'charger_delivered')::boolean,false),nullif(p_attributes->>'charger_status',''),now())
  on conflict(fk_customer_device_id) do update set fk_processor_model_id=excluded.fk_processor_model_id,gpu_brand_id=excluded.gpu_brand_id,gpu_family_id=excluded.gpu_family_id,gpu_model_id=excluded.gpu_model_id,fk_display_size_id=excluded.fk_display_size_id,fk_display_resolution_id=excluded.fk_display_resolution_id,fk_display_technology_id=excluded.fk_display_technology_id,fk_display_refresh_rate_id=excluded.fk_display_refresh_rate_id,display_touch=excluded.display_touch,battery_present=excluded.battery_present,battery_functional_status=excluded.battery_functional_status,charger_delivered=excluded.charger_delivered,charger_condition=excluded.charger_condition,updated_at=now();
  return v_device_id;
end $$;

revoke all on function public.save_customer_device_step_two(uuid,uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb,jsonb,uuid[]) from public,anon;
grant execute on function public.save_customer_device_step_two(uuid,uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb,jsonb,uuid[]) to authenticated;

commit;
