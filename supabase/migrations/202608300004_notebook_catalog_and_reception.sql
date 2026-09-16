-- Notebook: un único tipo activo y configuración específica, sin borrar historial.
update public.device_types set is_active = false
where organization_id is null
  and public.normalize_catalog_name(name) in (
    public.normalize_catalog_name('Notebook / Laptop'),
    public.normalize_catalog_name('Laptop')
  );
update public.device_types set is_active = true
where organization_id is null and public.normalize_catalog_name(name) = public.normalize_catalog_name('Notebook');

-- Catálogo propio del montaje de teclado. Las imágenes se administran desde
-- Storage/CMS y se guardan como URL/referencia, nunca en componentes React.
create table public.notebook_keyboard_mount_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 2 and 100),
  description text not null check (char_length(btrim(description)) between 10 and 1000),
  image_reference text check (image_reference is null or char_length(btrim(image_reference)) <= 500),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index notebook_keyboard_mount_types_global_unique on public.notebook_keyboard_mount_types(normalized_name) where organization_id is null;
create unique index notebook_keyboard_mount_types_org_unique on public.notebook_keyboard_mount_types(organization_id, normalized_name) where organization_id is not null;
alter table public.notebook_keyboard_mount_types enable row level security;
grant select on public.notebook_keyboard_mount_types to authenticated;
create policy notebook_keyboard_mount_types_read on public.notebook_keyboard_mount_types for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());

-- Los nombres/descripciones son datos de catálogo, no fallbacks de UI.
insert into public.notebook_keyboard_mount_types(name,description) values
 ('Desmontable superior','Sale desde arriba mediante pestañas, clips o algunos tornillos; no requiere desmontar completamente la notebook.'),
 ('Desmontable inferior','Es una pieza independiente, pero se accede desmontando la notebook desde debajo del palmrest.'),
 ('Integrado remachado','Está debajo del palmrest y fijado con remaches o plástico termosellado; reemplazarlo requiere reconstruir fijaciones.'),
 ('Integrado en Top Case','Forma parte del conjunto superior y normalmente se reemplaza el palmrest o top case completo.')
on conflict do nothing;

-- Controles funcionales de recepción: cada tipo configura qué se prueba, y no
-- duplica características permanentes del dispositivo.
create table public.device_reception_controls (
  id uuid primary key default gen_random_uuid(),
  device_type_id uuid not null references public.device_types(id) on delete restrict,
  key text not null check (key ~ '^[a-z][a-z0-9_]{1,60}$'),
  label text not null check (char_length(btrim(label)) between 2 and 120),
  applicable_when_attribute text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(device_type_id,key)
);
create index device_reception_controls_type_idx on public.device_reception_controls(device_type_id,sort_order) where is_active;
alter table public.device_reception_controls enable row level security;
grant select on public.device_reception_controls to authenticated;
create policy device_reception_controls_read on public.device_reception_controls for select to authenticated using (exists(select 1 from public.device_types t where t.id=device_reception_controls.device_type_id and (t.organization_id is null or t.organization_id=public.current_organization_id())));

-- Extiende las fuentes seguras del motor; ninguna es SQL enviado por cliente.
alter table public.device_fields drop constraint device_fields_data_source_key_check;
alter table public.device_fields add constraint device_fields_data_source_key_check check (data_source_key is null or data_source_key in ('brand','family','model','variant','color','memory_capacity','storage_capacity','operating_system','mobile_operator','accessory','lock_type','hardware_processor_brand','hardware_processor_model','hardware_motherboard_brand','hardware_motherboard_model','hardware_gpu_brand','hardware_gpu_model','hardware_power_supply_brand','hardware_power_supply_model','hardware_case_brand','hardware_case_model','hardware_cpu_cooler_brand','hardware_cpu_cooler_model','hardware_wifi_brand','hardware_wifi_model','notebook_keyboard_mount'));
insert into public.device_fields(key,label,field_type,data_source_key,placeholder,validation) values
 ('notebook_processor_brand_id','Marca del procesador','SELECT','hardware_processor_brand','Seleccionar marca','{}'),
 ('notebook_processor_model_id','Procesador','SELECT','hardware_processor_model','Seleccionar procesador','{}'),
 ('screen_inches','Pantalla (pulgadas)','NUMBER',null,'Ej. 15.6','{"min_value":1,"max_value":100}'),
 ('screen_resolution','Resolución','TEXT',null,null,'{"max_length":80}'),
 ('screen_panel_type','Tipo de panel','TEXT',null,null,'{"max_length":80}'),
 ('has_battery','¿Posee batería?','SWITCH',null,null,'{}'),
 ('battery_kind','Tipo de batería','SELECT',null,'Seleccionar tipo','{}'),
 ('battery_model','Modelo de batería','TEXT',null,null,'{"max_length":160}'),
 ('charger_received','¿El cliente entregó cargador?','SWITCH',null,null,'{}'),
 ('charger_kind','Tipo de cargador recibido','SELECT',null,'Seleccionar tipo','{}'),
 ('charger_original_model_power','Modelo / potencia del cargador original','TEXT',null,null,'{"max_length":160}'),
 ('charger_generic_brand','Marca del cargador alternativo','TEXT',null,null,'{"max_length":120}'),
 ('charger_generic_model','Modelo del cargador alternativo','TEXT',null,null,'{"max_length":160}'),
 ('charger_generic_power','Potencia del cargador alternativo','TEXT',null,null,'{"max_length":80}'),
 ('has_wifi','Wi-Fi','SWITCH',null,null,'{}'),('has_bluetooth','Bluetooth','SWITCH',null,null,'{}'),('has_ethernet','Ethernet','SWITCH',null,null,'{}'),('other_connectivity','Otras conectividades','TEXT',null,null,'{"max_length":300}'),
 ('has_optical_drive','¿Posee unidad óptica?','SWITCH',null,null,'{}'),('optical_drive_type','Tipo de unidad óptica','TEXT',null,null,'{"max_length":100}'),('optical_drive_mode','Modo de unidad óptica','SELECT',null,'Seleccionar modo','{}'),
 ('keyboard_mount_type','Montaje del teclado','SELECT','notebook_keyboard_mount','Seleccionar montaje','{}'),('keyboard_layout','Distribución / idioma','TEXT',null,null,'{"max_length":80}'),('has_numpad','¿Tiene teclado numérico?','SWITCH',null,null,'{}'),('has_keyboard_backlight','¿Tiene retroiluminación?','SWITCH',null,null,'{}'),('has_touchpad','¿Posee touchpad?','SWITCH',null,null,'{}')
on conflict do nothing;
insert into public.device_field_options(field_id,value,label,sort_order)
select f.id,v.value,v.label,v.sort_order from public.device_fields f join (values
 ('battery_kind','INTERNAL','Interna / integrada',1),('battery_kind','REMOVABLE','Extraíble',2),
 ('charger_kind','ORIGINAL','Original',1),('charger_kind','GENERIC','Genérico / alternativo',2),
 ('optical_drive_mode','READER','Lector',1),('optical_drive_mode','WRITER','Lector / grabadora',2)
) v(field_key,value,label,sort_order) on f.key=v.field_key and f.organization_id is null on conflict do nothing;

-- El notebook no hereda gabinete, fuente ni coolers de PC.
update public.device_type_fields tf set is_active=false from public.device_types t where tf.device_type_id=t.id and t.organization_id is null and t.name='Notebook';
insert into public.device_form_sections(device_type_id,key,title,sort_order)
select t.id,v.key,v.title,v.sort_order from public.device_types t cross join (values ('notebook_hardware','Hardware',10),('notebook_power','Energía y cargador',20),('notebook_connectivity','Conectividad y periféricos',30)) v(key,title,sort_order) where t.organization_id is null and t.name='Notebook' on conflict do nothing;
with a(section_key,field_key,sort_order) as (values
 ('notebook_hardware','notebook_processor_brand_id',10),('notebook_hardware','notebook_processor_model_id',20),('notebook_hardware','screen_inches',30),('notebook_hardware','screen_resolution',40),('notebook_hardware','screen_panel_type',50),('notebook_hardware','keyboard_mount_type',60),('notebook_hardware','keyboard_layout',70),('notebook_hardware','has_numpad',80),('notebook_hardware','has_keyboard_backlight',90),('notebook_hardware','has_touchpad',100),
 ('notebook_power','has_battery',10),('notebook_power','battery_kind',20),('notebook_power','battery_model',30),('notebook_power','charger_received',40),('notebook_power','charger_kind',50),('notebook_power','charger_original_model_power',60),('notebook_power','charger_generic_brand',70),('notebook_power','charger_generic_model',80),('notebook_power','charger_generic_power',90),
 ('notebook_connectivity','has_wifi',10),('notebook_connectivity','has_bluetooth',20),('notebook_connectivity','has_ethernet',30),('notebook_connectivity','other_connectivity',40),('notebook_connectivity','has_optical_drive',50),('notebook_connectivity','optical_drive_type',60),('notebook_connectivity','optical_drive_mode',70)
) insert into public.device_type_fields(device_type_id,section_id,field_id,sort_order) select t.id,s.id,f.id,a.sort_order from a join public.device_types t on t.organization_id is null and t.name='Notebook' join public.device_form_sections s on s.device_type_id=t.id and s.key=a.section_key and s.organization_id is null join public.device_fields f on f.key=a.field_key and f.organization_id is null on conflict(device_type_id,section_id,field_id) do update set is_active=true,sort_order=excluded.sort_order;

insert into public.device_reception_controls(device_type_id,key,label,applicable_when_attribute,sort_order)
select t.id,v.key,v.label,v.applies,v.sort_order from public.device_types t cross join (values
 ('screen','Pantalla',null,10),('battery','Batería','has_battery',20),('keyboard','Teclado',null,30),('touchpad','Touchpad','has_touchpad',40),('wifi','Wi-Fi / conectividad','has_wifi',50),('optical_drive','Unidad óptica','has_optical_drive',60),('charger','Cargador recibido','charger_received',70)
) v(key,label,applies,sort_order) where t.organization_id is null and t.name='Notebook' on conflict(device_type_id,key) do update set label=excluded.label,applicable_when_attribute=excluded.applicable_when_attribute,sort_order=excluded.sort_order,is_active=true;

-- El contrato existente se conserva, pero los vacíos opcionales no se
-- persisten como strings: se eliminan del JSON y colecciones vacías son NULL.
create or replace function public.create_customer_device_dynamic(
  p_customer_id uuid,p_type_id uuid,p_brand_id uuid,p_model_id uuid,p_model text,p_year text,p_color text,p_serial_number text,p_imei_1 text,p_imei_2 text,p_attributes jsonb,p_memories jsonb,p_storage_units jsonb,p_accessories text[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_device_id uuid; v_is_pc boolean; v_is_notebook boolean; v_model text:=regexp_replace(btrim(coalesce(p_model,'')),'[[:space:]]+',' ','g'); v_attributes jsonb;
begin
  select name='PC',name='Notebook' into v_is_pc,v_is_notebook from public.device_types where id=p_type_id;
  if not coalesce(v_is_pc,false) and char_length(v_model) < 2 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into v_attributes from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) where nullif(regexp_replace(trim(value #>> '{}'),'[[:space:]]+',' ','g'),'') is not null;
  v_device_id:=public.create_customer_device_dynamic_legacy(p_customer_id,p_type_id,p_brand_id,p_model_id,case when coalesce(v_is_pc,false) and v_model='' then '__unknown__' else v_model end,p_year,p_color,p_serial_number,p_imei_1,p_imei_2,v_attributes,p_memories,p_storage_units,p_accessories);
  update public.customer_devices set model=case when coalesce(v_is_pc,false) and v_model='' then null else model end, memory_modules=case when coalesce(v_is_notebook,false) and coalesce(jsonb_array_length(p_memories),0)=0 then null else memory_modules end, storage_units=case when coalesce(v_is_notebook,false) and coalesce(jsonb_array_length(p_storage_units),0)=0 then null else storage_units end, accessories=case when coalesce(v_is_notebook,false) and coalesce(cardinality(p_accessories),0)=0 then null else accessories end where id=v_device_id;
  return v_device_id;
end; $$;
