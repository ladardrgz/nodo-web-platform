-- Catálogos normalizados y formulario exclusivo para PC de escritorio.
-- No altera snapshots ni borra atributos históricos.

-- Mini PC deja de ser una categoría seleccionable: las recepciones históricas
-- conservan su type_id y sólo se desactiva para nuevas altas.
update public.device_types
set is_active = false
where organization_id is null
  and public.normalize_catalog_name(name) = public.normalize_catalog_name('Mini PC');

create table public.hardware_catalog_brands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('PROCESSOR','MOTHERBOARD','GPU','POWER_SUPPLY','CASE','CPU_COOLER','WIFI_ADAPTER')),
  name text not null check (char_length(btrim(name)) between 2 and 120),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index hardware_catalog_brands_global_unique on public.hardware_catalog_brands(kind, normalized_name) where organization_id is null;
create unique index hardware_catalog_brands_org_unique on public.hardware_catalog_brands(organization_id, kind, normalized_name) where organization_id is not null;
create index hardware_catalog_brands_read_idx on public.hardware_catalog_brands(kind, organization_id, name) where is_active;

create table public.hardware_catalog_models (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  kind text not null check (kind in ('PROCESSOR','MOTHERBOARD','GPU','POWER_SUPPLY','CASE','CPU_COOLER','WIFI_ADAPTER')),
  brand_id uuid not null references public.hardware_catalog_brands(id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 2 and 200),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, kind, brand_id)
);
create unique index hardware_catalog_models_global_unique on public.hardware_catalog_models(kind, brand_id, normalized_name) where organization_id is null;
create unique index hardware_catalog_models_org_unique on public.hardware_catalog_models(organization_id, kind, brand_id, normalized_name) where organization_id is not null;
create index hardware_catalog_models_read_idx on public.hardware_catalog_models(kind, brand_id, organization_id, name) where is_active;

alter table public.hardware_catalog_brands enable row level security;
alter table public.hardware_catalog_models enable row level security;
grant select on public.hardware_catalog_brands, public.hardware_catalog_models to authenticated;
create policy hardware_catalog_brands_read on public.hardware_catalog_brands for select to authenticated using (organization_id is null or organization_id = public.current_organization_id());
create policy hardware_catalog_models_read on public.hardware_catalog_models for select to authenticated using (organization_id is null or organization_id = public.current_organization_id());

-- Los únicos valores iniciales solicitados: marcas de procesador. Los modelos
-- quedan vacíos hasta que una organización los registre de forma autorizada.
insert into public.hardware_catalog_brands(kind, name) values ('PROCESSOR','AMD'), ('PROCESSOR','Intel') on conflict do nothing;

create or replace function public.create_hardware_catalog_model(
  p_kind text,
  p_brand_id uuid,
  p_name text
) returns public.hardware_catalog_models
language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid := public.assert_reception_owner();
  v_kind text := upper(btrim(coalesce(p_kind, '')));
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '[[:space:]]+', ' ', 'g');
  v_brand public.hardware_catalog_brands;
  v_existing public.hardware_catalog_models;
  v_created public.hardware_catalog_models;
begin
  if v_kind not in ('PROCESSOR','MOTHERBOARD','GPU','POWER_SUPPLY','CASE','CPU_COOLER','WIFI_ADAPTER') then raise exception 'INVALID_HARDWARE_KIND'; end if;
  if char_length(v_name) not between 2 and 200 then raise exception 'INVALID_HARDWARE_MODEL'; end if;
  select * into v_brand from public.hardware_catalog_brands
    where id = p_brand_id and kind = v_kind and is_active and (organization_id is null or organization_id = v_org);
  if not found then raise exception 'INVALID_HARDWARE_BRAND'; end if;
  select * into v_existing from public.hardware_catalog_models
    where kind = v_kind and brand_id = p_brand_id and normalized_name = public.normalize_catalog_name(v_name)
      and is_active and (organization_id is null or organization_id = v_org)
    order by organization_id nulls first limit 1;
  if found then return v_existing; end if;
  insert into public.hardware_catalog_models(organization_id, kind, brand_id, name, created_by)
  values (v_org, v_kind, p_brand_id, v_name, auth.uid())
  on conflict (organization_id, kind, brand_id, normalized_name) where organization_id is not null do update set name = hardware_catalog_models.name
  returning * into v_created;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values(v_org, auth.uid(), 'HARDWARE_CATALOG_MODEL_CREATED', 'HARDWARE_CATALOG_MODEL', v_created.id, jsonb_build_object('kind', v_kind, 'brand_id', p_brand_id));
  return v_created;
end; $$;
revoke all on function public.create_hardware_catalog_model(text, uuid, text) from public, anon;
grant execute on function public.create_hardware_catalog_model(text, uuid, text) to authenticated;

-- Extiende el motor existente sin permitir claves arbitrarias de fuentes.
alter table public.device_fields drop constraint device_fields_data_source_key_check;
alter table public.device_fields add constraint device_fields_data_source_key_check check (data_source_key is null or data_source_key in ('brand','family','model','variant','color','memory_capacity','storage_capacity','operating_system','mobile_operator','accessory','lock_type','hardware_processor_brand','hardware_processor_model','hardware_motherboard_brand','hardware_motherboard_model','hardware_gpu_brand','hardware_gpu_model','hardware_power_supply_brand','hardware_power_supply_model','hardware_case_brand','hardware_case_model','hardware_cpu_cooler_brand','hardware_cpu_cooler_model','hardware_wifi_brand','hardware_wifi_model'));

insert into public.device_fields(key,label,field_type,data_source_key,placeholder,validation) values
 ('processor_brand_id','Marca del procesador','SELECT','hardware_processor_brand','Seleccionar marca','{}'),
 ('processor_model_id','Procesador','SELECT','hardware_processor_model','Seleccionar procesador','{}'),
 ('motherboard_brand_id','Marca de la placa madre','SELECT','hardware_motherboard_brand','Seleccionar marca','{}'),
 ('motherboard_model_id','Placa madre / Motherboard','SELECT','hardware_motherboard_model','Seleccionar modelo','{}'),
 ('graphics_mode','Gráficos','SELECT',null,'Seleccionar opción','{}'),
 ('gpu_brand_id','Marca de tarjeta gráfica','SELECT','hardware_gpu_brand','Seleccionar marca','{}'),
 ('gpu_model_id','Tarjeta gráfica dedicada','SELECT','hardware_gpu_model','Seleccionar tarjeta gráfica','{}'),
 ('case_brand_id','Marca del gabinete','SELECT','hardware_case_brand','Seleccionar marca','{}'),
 ('case_model_id','Modelo del gabinete','SELECT','hardware_case_model','Seleccionar modelo','{}'),
 ('case_fan_count','Cantidad de coolers/ventiladores','NUMBER',null,null,'{"min_value":0,"max_value":50}'),
 ('case_has_original_power_supply','¿El gabinete incluye la fuente de alimentación original?','SWITCH',null,null,'{}'),
 ('included_power_supply_name','Fuente incluida: nombre/modelo completo','TEXT',null,'Ej. BRB 500W','{"max_length":200}'),
 ('external_power_supply_brand_id','Marca de fuente externa','SELECT','hardware_power_supply_brand','Seleccionar marca','{}'),
 ('external_power_supply_model_id','Fuente de alimentación externa','SELECT','hardware_power_supply_model','Seleccionar fuente','{}'),
 ('cpu_cooler_mode','Refrigeración del procesador','SELECT',null,'Seleccionar opción','{}'),
 ('cpu_cooler_brand_id','Marca del cooler independiente','SELECT','hardware_cpu_cooler_brand','Seleccionar marca','{}'),
 ('cpu_cooler_model_id','Cooler independiente','SELECT','hardware_cpu_cooler_model','Seleccionar modelo','{}'),
 ('operating_system_kind','Sistema operativo','SELECT',null,'Seleccionar sistema','{}'),
 ('operating_system_version','Versión / distribución','TEXT',null,'Ej. Windows 11 Pro o Ubuntu 24.04','{"max_length":120}'),
 ('has_wifi','¿Posee Wi-Fi?','SWITCH',null,null,'{}'),
 ('wifi_mode','Tipo de Wi-Fi','SELECT',null,'Seleccionar tipo','{}'),
 ('wifi_brand_id','Marca del adaptador/tarjeta Wi-Fi','SELECT','hardware_wifi_brand','Seleccionar marca','{}'),
 ('wifi_model_id','Adaptador/tarjeta Wi-Fi','SELECT','hardware_wifi_model','Seleccionar modelo','{}'),
 ('has_optical_drive','¿Posee lector/grabadora de CD/DVD?','SWITCH',null,null,'{}'),
 ('internal_accessories','Cables y accesorios internos','TEXTAREA',null,'Registrar uno por línea','{"max_length":1200}')
on conflict do nothing;

insert into public.device_field_options(field_id,value,label,sort_order)
select f.id, v.value, v.label, v.sort_order from public.device_fields f join (values
 ('graphics_mode','INTEGRATED','Gráficos integrados',1),('graphics_mode','DEDICATED','Tarjeta gráfica dedicada',2),
 ('cpu_cooler_mode','ORIGINAL','Cooler incluido/original del procesador',1),('cpu_cooler_mode','EXTERNAL','Cooler independiente',2),
 ('operating_system_kind','WINDOWS','Windows',1),('operating_system_kind','LINUX','Linux',2),('operating_system_kind','MACOS','macOS',3),('operating_system_kind','OTHER','Otro',4),('operating_system_kind','NONE','Sin sistema operativo',5),
 ('wifi_mode','INTEGRATED','Wi-Fi integrado',1),('wifi_mode','EXTERNAL','Adaptador/tarjeta externa',2)
) as v(field_key,value,label,sort_order) on f.key=v.field_key and f.organization_id is null
on conflict do nothing;

-- Desactiva las asignaciones PC genéricas y crea la única definición actual.
update public.device_type_fields tf set is_active=false
from public.device_types t
where tf.device_type_id=t.id and t.organization_id is null and t.name='PC de escritorio';
insert into public.device_form_sections(device_type_id,key,title,sort_order)
select t.id,v.key,v.title,v.sort_order from public.device_types t cross join (values
 ('desktop_hardware','Hardware',10),('desktop_case','Gabinete y fuente',20),('desktop_system','Sistema y conectividad',30)
) v(key,title,sort_order) where t.organization_id is null and t.name='PC de escritorio'
on conflict do nothing;
with assignments(section_key,field_key,sort_order,required) as (values
 ('desktop_hardware','processor_brand_id',10,false),('desktop_hardware','processor_model_id',20,false),('desktop_hardware','motherboard_brand_id',30,false),('desktop_hardware','motherboard_model_id',40,false),('desktop_hardware','graphics_mode',50,false),('desktop_hardware','gpu_brand_id',60,false),('desktop_hardware','gpu_model_id',70,false),
 ('desktop_case','case_brand_id',10,false),('desktop_case','case_model_id',20,false),('desktop_case','case_fan_count',30,false),('desktop_case','case_has_original_power_supply',40,false),('desktop_case','included_power_supply_name',50,false),('desktop_case','external_power_supply_brand_id',60,false),('desktop_case','external_power_supply_model_id',70,false),('desktop_case','cpu_cooler_mode',80,false),('desktop_case','cpu_cooler_brand_id',90,false),('desktop_case','cpu_cooler_model_id',100,false),
 ('desktop_system','operating_system_kind',10,false),('desktop_system','operating_system_version',20,false),('desktop_system','has_wifi',30,false),('desktop_system','wifi_mode',40,false),('desktop_system','wifi_brand_id',50,false),('desktop_system','wifi_model_id',60,false),('desktop_system','has_optical_drive',70,false),('desktop_system','internal_accessories',80,false)
) insert into public.device_type_fields(device_type_id,section_id,field_id,sort_order,required)
select t.id,s.id,f.id,a.sort_order,a.required from assignments a join public.device_types t on t.organization_id is null and t.name='PC de escritorio' join public.device_form_sections s on s.device_type_id=t.id and s.key=a.section_key and s.organization_id is null join public.device_fields f on f.key=a.field_key and f.organization_id is null
on conflict(device_type_id,section_id,field_id) do update set is_active=true, sort_order=excluded.sort_order, required=excluded.required;

insert into public.device_field_dependencies(device_type_field_id,parent_device_type_field_id,operator,expected_value)
select child.id,parent.id,'NOT_EMPTY',null from public.device_type_fields child join public.device_fields cf on cf.id=child.field_id join public.device_type_fields parent on parent.device_type_id=child.device_type_id join public.device_fields pf on pf.id=parent.field_id
where cf.key in ('processor_model_id','motherboard_model_id','gpu_model_id','case_model_id','external_power_supply_model_id','cpu_cooler_model_id','wifi_model_id') and pf.key=replace(cf.key,'_model_id','_brand_id') and child.is_active and parent.is_active
on conflict do nothing;
insert into public.device_field_dependencies(device_type_field_id,parent_device_type_field_id,operator,expected_value)
select child.id,parent.id,'EQUALS','"DEDICATED"'::jsonb from public.device_type_fields child join public.device_fields cf on cf.id=child.field_id join public.device_type_fields parent on parent.device_type_id=child.device_type_id join public.device_fields pf on pf.id=parent.field_id
where cf.key in ('gpu_brand_id','gpu_model_id') and pf.key='graphics_mode' and child.is_active and parent.is_active
on conflict do nothing;
insert into public.device_field_dependencies(device_type_field_id,parent_device_type_field_id,operator,expected_value)
select child.id,parent.id,'EQUALS',to_jsonb(v.expected_value) from (values
 ('included_power_supply_name','case_has_original_power_supply','true'),
 ('external_power_supply_brand_id','case_has_original_power_supply','false'),
 ('external_power_supply_model_id','case_has_original_power_supply','false'),
 ('cpu_cooler_brand_id','cpu_cooler_mode','EXTERNAL'),
 ('cpu_cooler_model_id','cpu_cooler_mode','EXTERNAL'),
 ('wifi_mode','has_wifi','true'),
 ('wifi_brand_id','wifi_mode','EXTERNAL'),
 ('wifi_model_id','wifi_mode','EXTERNAL')
) v(child_key,parent_key,expected_value)
join public.device_type_fields child on child.is_active join public.device_fields cf on cf.id=child.field_id and cf.key=v.child_key
join public.device_type_fields parent on parent.device_type_id=child.device_type_id and parent.is_active join public.device_fields pf on pf.id=parent.field_id and pf.key=v.parent_key
on conflict do nothing;

alter table public.customer_devices alter column model drop not null;

-- La verificación diferida evita depender del orden de claves del JSON enviado
-- por el cliente y mantiene el par marca/modelo íntegro dentro de la transacción.
create or replace function public.validate_desktop_hardware_values()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_org uuid; v_type text; v_processor_brand uuid; v_processor_model uuid;
begin
  select d.organization_id,t.name into v_org,v_type from public.customer_devices d join public.device_types t on t.id=d.type_id where d.id=new.customer_device_id;
  if v_type is distinct from 'PC de escritorio' then return null; end if;
  select nullif(value_text,'')::uuid into v_processor_brand from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_brand_id';
  select nullif(value_text,'')::uuid into v_processor_model from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_model_id';
  if v_processor_model is not null and not exists (select 1 from public.hardware_catalog_models m where m.id=v_processor_model and m.kind='PROCESSOR' and m.brand_id=v_processor_brand and m.is_active and (m.organization_id is null or m.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_MODEL'; end if;
  if v_processor_brand is not null and not exists (select 1 from public.hardware_catalog_brands b where b.id=v_processor_brand and b.kind='PROCESSOR' and b.is_active and (b.organization_id is null or b.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_BRAND'; end if;
  return null;
end; $$;
create constraint trigger customer_device_pc_hardware_validation
after insert or update on public.customer_device_field_values deferrable initially deferred
for each row execute function public.validate_desktop_hardware_values();
revoke all on function public.validate_desktop_hardware_values() from public, anon, authenticated;

-- Mantiene el contrato de la RPC existente y habilita modelo de equipo desconocido
-- sólo para PC de escritorio, sin inventar un valor de dominio persistido.
alter function public.create_customer_device_dynamic(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) rename to create_customer_device_dynamic_legacy;
create function public.create_customer_device_dynamic(
  p_customer_id uuid,p_type_id uuid,p_brand_id uuid,p_model_id uuid,p_model text,p_year text,p_color text,p_serial_number text,p_imei_1 text,p_imei_2 text,p_attributes jsonb,p_memories jsonb,p_storage_units jsonb,p_accessories text[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_device_id uuid; v_is_desktop boolean; v_model text:=regexp_replace(btrim(coalesce(p_model,'')),'[[:space:]]+',' ','g');
begin
  select name='PC de escritorio' into v_is_desktop from public.device_types where id=p_type_id;
  if not coalesce(v_is_desktop,false) and char_length(v_model) < 2 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  v_device_id:=public.create_customer_device_dynamic_legacy(p_customer_id,p_type_id,p_brand_id,p_model_id,case when coalesce(v_is_desktop,false) and v_model='' then '__unknown__' else v_model end,p_year,p_color,p_serial_number,p_imei_1,p_imei_2,p_attributes,p_memories,p_storage_units,p_accessories);
  if coalesce(v_is_desktop,false) and v_model='' then update public.customer_devices set model=null where id=v_device_id; end if;
  return v_device_id;
end; $$;
revoke all on function public.create_customer_device_dynamic(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) from public,anon;
grant execute on function public.create_customer_device_dynamic(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) to authenticated;
