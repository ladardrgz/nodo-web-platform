begin;

alter table public.device_form_sections
  add column if not exists ui_config jsonb not null default '{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb;

alter table public.device_form_sections
  add constraint device_form_sections_ui_config_object
  check (jsonb_typeof(ui_config) = 'object') not valid;
alter table public.device_form_sections validate constraint device_form_sections_ui_config_object;

with section_seed(key,title,description,sort_order,ui_config) as (
  values
    ('notebook_identification','Identificación','Marca, modelo y datos identificatorios del equipo.',10,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_processor','Procesador','Selección dependiente desde el catálogo técnico.',20,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_memory','Memoria RAM','Módulos físicos instalados en el equipo.',30,'{"container":"repeatable-section","columns":{"base":1,"md":1},"gap":"md"}'::jsonb),
    ('notebook_graphics','Gráficos','Configuración gráfica integrada o dedicada.',40,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_storage','Almacenamiento','Unidades físicas instaladas.',50,'{"container":"repeatable-section","columns":{"base":1,"md":1},"gap":"md"}'::jsonb),
    ('notebook_display','Pantalla','Características del panel.',60,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_power','Batería y cargador','Estado y características de alimentación.',70,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_operating_system','Sistema operativo','Sistema instalado en el dispositivo.',80,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_connectivity','Conectividad','Interfaces de red y conectividad.',90,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb),
    ('notebook_ports','Puertos','Conectores físicos disponibles.',100,'{"container":"repeatable-section","columns":{"base":1,"md":1},"gap":"md"}'::jsonb),
    ('notebook_accessories','Accesorios','Accesorios recibidos con el equipo.',110,'{"container":"section","columns":{"base":1,"md":2},"gap":"md"}'::jsonb)
)
insert into public.device_form_sections(key,title,description,alcance,fk_organizacion_id,is_active,sort_order,ui_config)
select key,title,description,'GLOBAL',null,true,sort_order,ui_config from section_seed
on conflict (key,fk_organizacion_id) do update
set title=excluded.title,description=excluded.description,is_active=true,sort_order=excluded.sort_order,ui_config=excluded.ui_config,updated_at=now();

with field_seed(key,label,field_type,data_source_key,placeholder,help_text,validation) as (
  values
    ('ram_modules','Memorias RAM','REPEATABLE',null,null,'Cada módulo se persiste como un registro independiente.','{}'::jsonb),
    ('storage_drives','Almacenamientos','REPEATABLE',null,null,'Cada unidad se persiste como un registro independiente.','{}'::jsonb),
    ('device_ports','Puertos','REPEATABLE',null,null,'Cada conector se persiste como un registro independiente.','{}'::jsonb),
    ('device_accessories','Accesorios','MULTISELECT','accessory','Seleccionar accesorios',null,'{}'::jsonb),
    ('gpu_brand_id','Fabricante GPU','SELECT',null,'Seleccionar fabricante',null,'{}'::jsonb),
    ('gpu_family_id','Familia GPU','SELECT',null,'Primero seleccioná un fabricante',null,'{}'::jsonb),
    ('gpu_model_id','Modelo GPU','SELECT',null,'Primero seleccioná una familia',null,'{}'::jsonb),
    ('operating_system_id','Sistema operativo','SELECT','operating_system','Seleccionar sistema operativo',null,'{}'::jsonb),
    ('battery_present','Batería presente','SWITCH',null,null,null,'{}'::jsonb),
    ('battery_status','Estado de batería','RADIO',null,null,null,'{}'::jsonb),
    ('charger_delivered','Cargador entregado','SWITCH',null,null,null,'{}'::jsonb),
    ('charger_status','Estado del cargador','RADIO',null,null,null,'{}'::jsonb),
    ('screen_technology','Tecnología','SELECT',null,'Seleccionar tecnología',null,'{}'::jsonb),
    ('screen_refresh_rate','Frecuencia','SELECT',null,'Seleccionar frecuencia',null,'{}'::jsonb),
    ('screen_touch','Pantalla táctil','SWITCH',null,null,null,'{}'::jsonb),
    ('connectivity','Conectividad','REPEATABLE',null,null,'Interfaces de conectividad disponibles.','{}'::jsonb)
)
insert into public.device_fields(key,label,field_type,data_source_key,placeholder,help_text,validation,alcance,fk_organizacion_id,is_active)
select key,label,field_type,data_source_key,placeholder,help_text,validation,'GLOBAL',null,true from field_seed
on conflict (key,fk_organizacion_id) do update
set label=excluded.label,field_type=excluded.field_type,data_source_key=excluded.data_source_key,placeholder=excluded.placeholder,help_text=excluded.help_text,validation=excluded.validation,is_active=true,updated_at=now();

update public.device_type_fields b
set sort_order=b.sort_order+10000,is_active=false
from public.device_types t,public.device_form_sections s
where b.fk_tipo_dispositivo_id=t.id and t.code='notebook'
  and b.fk_seccion_formulario_dispositivo_id=s.id
  and s.key in ('notebook_memory','notebook_graphics','notebook_storage','notebook_display','notebook_power','notebook_operating_system','notebook_connectivity','notebook_ports','notebook_accessories');

with notebook as (select id from public.device_types where code='notebook'),
binding_seed(section_key,field_key,sort_order,required,overrides) as (
  values
    ('notebook_memory','ram_modules',10,false,'{"component":"ram-modules","fullWidth":true}'::jsonb),
    ('notebook_graphics','gpu_brand_id',10,false,'{"component":"searchable-select","catalog":"gpu_brands"}'::jsonb),
    ('notebook_graphics','gpu_family_id',20,false,'{"component":"searchable-select","catalog":"gpu_families","dependsOn":"gpu_brand_id"}'::jsonb),
    ('notebook_graphics','gpu_model_id',30,false,'{"component":"searchable-select","catalog":"gpu_models","dependsOn":"gpu_family_id","compatibility":"notebook"}'::jsonb),
    ('notebook_storage','storage_drives',10,false,'{"component":"storage-drives","fullWidth":true}'::jsonb),
    ('notebook_display','screen_size',10,false,'{"component":"searchable-select","catalog":"legacy_display_size"}'::jsonb),
    ('notebook_display','screen_resolution',20,false,'{"component":"searchable-select","catalog":"legacy_display_resolution"}'::jsonb),
    ('notebook_display','screen_technology',30,false,'{"component":"searchable-select","catalog":"legacy_display_technology"}'::jsonb),
    ('notebook_display','screen_refresh_rate',40,false,'{"component":"searchable-select","catalog":"legacy_display_refresh_rate"}'::jsonb),
    ('notebook_display','screen_touch',50,false,'{"component":"checkbox"}'::jsonb),
    ('notebook_operating_system','operating_system_id',10,false,'{"component":"searchable-select"}'::jsonb),
    ('notebook_power','battery_present',10,false,'{"component":"checkbox"}'::jsonb),
    ('notebook_power','battery_status',20,false,'{"component":"radio-group"}'::jsonb),
    ('notebook_power','charger_delivered',30,false,'{"component":"checkbox"}'::jsonb),
    ('notebook_power','charger_status',40,false,'{"component":"radio-group"}'::jsonb),
    ('notebook_connectivity','connectivity',10,false,'{"component":"multi-select","fullWidth":true,"catalog":"legacy_connectivity"}'::jsonb),
    ('notebook_ports','device_ports',10,false,'{"component":"device-ports","fullWidth":true}'::jsonb),
    ('notebook_accessories','device_accessories',10,false,'{"component":"multi-select","fullWidth":true}'::jsonb)
)
insert into public.device_type_fields(fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,sort_order,required,overrides,is_active)
select n.id,s.id,f.id,b.sort_order,b.required,b.overrides,true
from notebook n cross join binding_seed b
join public.device_form_sections s on s.key=b.section_key and s.fk_organizacion_id is null
join public.device_fields f on f.key=b.field_key and f.fk_organizacion_id is null
on conflict (fk_tipo_dispositivo_id,fk_campo_dispositivo_id) do update
set fk_seccion_formulario_dispositivo_id=excluded.fk_seccion_formulario_dispositivo_id,
    sort_order=excluded.sort_order,required=excluded.required,overrides=excluded.overrides,is_active=true;

insert into public.device_field_options(fk_campo_dispositivo_id,value,label,sort_order,is_active)
select f.id,o.value,o.label,o.sort_order,true
from public.device_fields f
cross join (values
  ('GOOD','Bueno',10),('WEAR','Con desgaste',20),('DAMAGED','Dañado',30),('NOT_TESTED','Sin probar',40)
) o(value,label,sort_order)
where f.key in ('battery_status','charger_status') and f.fk_organizacion_id is null
and not exists (
  select 1 from public.device_field_options x
  where x.fk_campo_dispositivo_id=f.id and lower(x.value)=lower(o.value)
);

insert into public.device_brands(name,alcance,fk_organizacion_id,is_active)
select 'GFAST','GLOBAL',null,true
where not exists(select 1 from public.device_brands where normalized_name=public.normalize_catalog_name('GFAST') and fk_organizacion_id is null);
insert into public.device_type_brands(fk_tipo_dispositivo_id,fk_marca_dispositivo_id)
select t.id,b.id from public.device_types t cross join public.device_brands b
where t.code='notebook' and b.normalized_name=public.normalize_catalog_name('GFAST') and b.fk_organizacion_id is null
on conflict do nothing;
insert into public.device_models(fk_tipo_dispositivo_id,fk_marca_dispositivo_id,name,alcance,fk_organizacion_id,is_active)
select t.id,b.id,'N-750','GLOBAL',null,true from public.device_types t cross join public.device_brands b
where t.code='notebook' and b.normalized_name=public.normalize_catalog_name('GFAST') and b.fk_organizacion_id is null
and not exists(select 1 from public.device_models m where m.fk_tipo_dispositivo_id=t.id and m.fk_marca_dispositivo_id=b.id and m.normalized_name=public.normalize_catalog_name('N-750') and m.fk_organizacion_id is null);

insert into public.processor_brands(nombre,activo)
select 'AMD',true where not exists(select 1 from public.processor_brands where nombre_normalizado=public.normalize_catalog_name('AMD'));
insert into public.processor_families(fk_marca_procesador_id,nombre,activo)
select b.id,'Ryzen 5',true from public.processor_brands b
where b.nombre_normalizado=public.normalize_catalog_name('AMD')
and not exists(select 1 from public.processor_families f where f.fk_marca_procesador_id=b.id and f.nombre_normalizado=public.normalize_catalog_name('Ryzen 5'));
insert into public.processor_generations(fk_processor_family_id,code,name,sort_order,is_active)
select f.id,'5000','5000',5000,true from public.processor_families f join public.processor_brands b on b.id=f.fk_marca_procesador_id
where b.nombre_normalizado=public.normalize_catalog_name('AMD') and f.nombre_normalizado=public.normalize_catalog_name('Ryzen 5')
on conflict(fk_processor_family_id,code) do update set name=excluded.name,is_active=true;
insert into public.processor_models(fk_familia_procesador_id,fk_processor_generation_id,nombre,alcance,fk_organizacion_id,activo)
select f.id,g.id,'Ryzen 5 5500U','GLOBAL',null,true
from public.processor_families f join public.processor_brands b on b.id=f.fk_marca_procesador_id
join public.processor_generations g on g.fk_processor_family_id=f.id and g.code='5000'
where b.nombre_normalizado=public.normalize_catalog_name('AMD') and f.nombre_normalizado=public.normalize_catalog_name('Ryzen 5')
and not exists(select 1 from public.processor_models m where m.fk_familia_procesador_id=f.id and m.nombre_normalizado=public.normalize_catalog_name('Ryzen 5 5500U') and m.fk_organizacion_id is null);
insert into public.processor_specifications(fk_processor_model_id,core_count,thread_count,base_clock_mhz,integrated_gpu,desktop_supported,notebook_supported)
select m.id,6,12,2100,true,false,true from public.processor_models m
where m.nombre_normalizado=public.normalize_catalog_name('Ryzen 5 5500U')
on conflict(fk_processor_model_id) do update set notebook_supported=true,desktop_supported=false;

insert into public.storage_types(nombre,alcance,fk_organizacion_id,activo)
values ('HDD','GLOBAL',null,true),('SSD','GLOBAL',null,true),('eMMC','GLOBAL',null,true)
on conflict (nombre_normalizado,fk_organizacion_id) do update set activo=true;

insert into public.gpu_brands(code,name) values ('intel','Intel'),('amd','AMD'),('nvidia','NVIDIA')
on conflict(code) do update set name=excluded.name,is_active=true;
insert into public.gpu_families(fk_gpu_brand_id,code,name)
select b.id,v.code,v.name from public.gpu_brands b join (values
  ('intel','iris_xe','Iris Xe'),('amd','vega','Vega'),('nvidia','rtx_30','RTX 30')
) v(brand_code,code,name) on v.brand_code=b.code
on conflict(fk_gpu_brand_id,code) do update set name=excluded.name,is_active=true;
insert into public.gpu_models(fk_gpu_family_id,code,name,graphics_kind,desktop_supported,notebook_supported)
select f.id,v.code,v.name,v.kind,v.desktop_supported,v.notebook_supported
from public.gpu_families f join public.gpu_brands b on b.id=f.fk_gpu_brand_id
join (values
  ('intel','iris_xe','iris_xe_graphics','Iris Xe Graphics','INTEGRATED',false,true),
  ('amd','vega','vega_8','Vega 8','INTEGRATED',false,true),
  ('nvidia','rtx_30','rtx_3050','RTX 3050','DEDICATED',true,true)
) v(brand_code,family_code,code,name,kind,desktop_supported,notebook_supported)
on b.code=v.brand_code and f.code=v.family_code
on conflict(fk_gpu_family_id,code) do update set name=excluded.name,graphics_kind=excluded.graphics_kind,desktop_supported=excluded.desktop_supported,notebook_supported=excluded.notebook_supported,is_active=true;

alter table public.customer_device_hardware_profiles
  add column if not exists gpu_brand_id uuid references public.gpu_brands(id) on delete restrict,
  add column if not exists gpu_family_id uuid references public.gpu_families(id) on delete restrict,
  add column if not exists gpu_model_id uuid references public.gpu_models(id) on delete restrict;

comment on column public.customer_device_hardware_profiles.fk_gpu_chip_brand_id is 'Legacy hardware_catalog_items FK; retained for compatibility only.';
comment on column public.customer_device_hardware_profiles.fk_gpu_family_id is 'Legacy hardware_catalog_items FK; retained for compatibility only.';
comment on column public.customer_device_hardware_profiles.fk_gpu_model_id is 'Legacy hardware_catalog_items FK; retained for compatibility only.';

create or replace function public.save_customer_device_step_two(
  p_customer_id uuid,p_device_type_id uuid,p_device_brand_id uuid,p_device_model_id uuid,
  p_serial_number text default null,p_observations text default null,p_customer_device_id uuid default null,
  p_attributes jsonb default '{}'::jsonb,p_ram_modules jsonb default '[]'::jsonb,
  p_storage_drives jsonb default '[]'::jsonb,p_ports jsonb default '[]'::jsonb,p_accessory_ids uuid[] default '{}'::uuid[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_device_id uuid; v_item jsonb;
begin
  perform public.assert_reception_owner();
  if jsonb_typeof(p_attributes)<>'object' or jsonb_typeof(p_ram_modules)<>'array' or jsonb_typeof(p_storage_drives)<>'array' or jsonb_typeof(p_ports)<>'array' then raise exception 'INVALID_DEVICE_DATA'; end if;
  v_device_id:=public.save_customer_device_identification(p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,p_serial_number,p_observations,p_customer_device_id);
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
  select v_device_id,value::uuid
  from jsonb_array_elements_text(coalesce(nullif(p_attributes->>'connectivity','')::jsonb,'[]'::jsonb));
  insert into public.customer_device_hardware_profiles(fk_customer_device_id,fk_processor_model_id,gpu_brand_id,gpu_family_id,gpu_model_id,fk_display_size_id,fk_display_resolution_id,fk_display_technology_id,fk_display_refresh_rate_id,display_touch,battery_present,battery_functional_status,charger_delivered,charger_condition,updated_at)
  values(v_device_id,nullif(p_attributes->>'processor_model_id','')::uuid,nullif(p_attributes->>'gpu_brand_id','')::uuid,nullif(p_attributes->>'gpu_family_id','')::uuid,nullif(p_attributes->>'gpu_model_id','')::uuid,
    nullif(p_attributes->>'screen_size','')::uuid,nullif(p_attributes->>'screen_resolution','')::uuid,nullif(p_attributes->>'screen_technology','')::uuid,nullif(p_attributes->>'screen_refresh_rate','')::uuid,coalesce((p_attributes->>'screen_touch')::boolean,false),
    coalesce((p_attributes->>'battery_present')::boolean,false),nullif(p_attributes->>'battery_status',''),coalesce((p_attributes->>'charger_delivered')::boolean,false),nullif(p_attributes->>'charger_status',''),now())
  on conflict(fk_customer_device_id) do update set fk_processor_model_id=excluded.fk_processor_model_id,gpu_brand_id=excluded.gpu_brand_id,gpu_family_id=excluded.gpu_family_id,gpu_model_id=excluded.gpu_model_id,fk_display_size_id=excluded.fk_display_size_id,fk_display_resolution_id=excluded.fk_display_resolution_id,fk_display_technology_id=excluded.fk_display_technology_id,fk_display_refresh_rate_id=excluded.fk_display_refresh_rate_id,display_touch=excluded.display_touch,battery_present=excluded.battery_present,battery_functional_status=excluded.battery_functional_status,charger_delivered=excluded.charger_delivered,charger_condition=excluded.charger_condition,updated_at=now();
  return v_device_id;
end $$;
revoke all on function public.save_customer_device_step_two(uuid,uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb,jsonb,uuid[]) from public,anon;
grant execute on function public.save_customer_device_step_two(uuid,uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb,jsonb,uuid[]) to authenticated;

commit;
