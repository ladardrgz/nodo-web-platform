-- Consolidación incremental de tipos de computadora de escritorio.
-- Conserva los dispositivos y recepciones históricos; sólo cambia el catálogo activo.

update public.device_types set name = 'PC'
where organization_id is null and public.normalize_catalog_name(name) = public.normalize_catalog_name('PC de escritorio');
update public.device_types set name = 'All-In-One - Todo en uno'
where organization_id is null and public.normalize_catalog_name(name) = public.normalize_catalog_name('All-in-One');
update public.device_types set name = 'Mini-PC'
where organization_id is null and public.normalize_catalog_name(name) = public.normalize_catalog_name('Mini PC');
update public.device_types set name = 'Estación de trabajo - Workstation', is_active = true
where organization_id is null and public.normalize_catalog_name(name) = public.normalize_catalog_name('Workstation');

insert into public.device_types(name, category, attribute_group)
values ('HPC', 'Computación', 'COMPUTER'), ('Embebidos - Embedded', 'Computación', 'COMPUTER')
on conflict do nothing;

-- PC gamer duplica PC y Servidor no es un tipo de PC de recepción general.
-- Se desactivan para nuevas altas, sin borrar referencias históricas.
update public.device_types set is_active = false
where organization_id is null and public.normalize_catalog_name(name) in (
  public.normalize_catalog_name('PC gamer'),
  public.normalize_catalog_name('Servidor')
);
update public.device_types set is_active = true
where organization_id is null and public.normalize_catalog_name(name) in (
  public.normalize_catalog_name('PC'),
  public.normalize_catalog_name('All-In-One - Todo en uno'),
  public.normalize_catalog_name('Mini-PC')
);

-- Las funciones de PC conservan el mismo type_id tras el renombre.
create or replace function public.validate_desktop_hardware_values()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_org uuid; v_type text; v_processor_brand uuid; v_processor_model uuid;
begin
  select d.organization_id,t.name into v_org,v_type from public.customer_devices d join public.device_types t on t.id=d.type_id where d.id=new.customer_device_id;
  if v_type is distinct from 'PC' then return null; end if;
  select nullif(value_text,'')::uuid into v_processor_brand from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_brand_id';
  select nullif(value_text,'')::uuid into v_processor_model from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_model_id';
  if v_processor_model is not null and not exists (select 1 from public.hardware_catalog_models m where m.id=v_processor_model and m.kind='PROCESSOR' and m.brand_id=v_processor_brand and m.is_active and (m.organization_id is null or m.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_MODEL'; end if;
  if v_processor_brand is not null and not exists (select 1 from public.hardware_catalog_brands b where b.id=v_processor_brand and b.kind='PROCESSOR' and b.is_active and (b.organization_id is null or b.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_BRAND'; end if;
  return null;
end; $$;

create or replace function public.create_customer_device_dynamic(
  p_customer_id uuid,p_type_id uuid,p_brand_id uuid,p_model_id uuid,p_model text,p_year text,p_color text,p_serial_number text,p_imei_1 text,p_imei_2 text,p_attributes jsonb,p_memories jsonb,p_storage_units jsonb,p_accessories text[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_device_id uuid; v_is_desktop boolean; v_model text:=regexp_replace(btrim(coalesce(p_model,'')),'[[:space:]]+',' ','g');
begin
  select name='PC' into v_is_desktop from public.device_types where id=p_type_id;
  if not coalesce(v_is_desktop,false) and char_length(v_model) < 2 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  v_device_id:=public.create_customer_device_dynamic_legacy(p_customer_id,p_type_id,p_brand_id,p_model_id,case when coalesce(v_is_desktop,false) and v_model='' then '__unknown__' else v_model end,p_year,p_color,p_serial_number,p_imei_1,p_imei_2,p_attributes,p_memories,p_storage_units,p_accessories);
  if coalesce(v_is_desktop,false) and v_model='' then update public.customer_devices set model=null where id=v_device_id; end if;
  return v_device_id;
end; $$;
