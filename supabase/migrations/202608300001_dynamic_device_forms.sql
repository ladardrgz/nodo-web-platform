-- Motor de formularios de recepción. Catálogos globales (organization_id null)
-- y privados por organización. No modifica ni elimina snapshots históricos.

create table if not exists public.device_form_sections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  device_type_id uuid not null references public.device_types(id) on delete restrict,
  key text not null check (key ~ '^[a-z][a-z0-9_]{1,60}$'),
  title text not null check (char_length(trim(title)) between 2 and 100),
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists device_form_sections_global_unique on public.device_form_sections(device_type_id, key) where organization_id is null;
create unique index if not exists device_form_sections_org_unique on public.device_form_sections(organization_id, device_type_id, key) where organization_id is not null;
create index if not exists device_form_sections_type_idx on public.device_form_sections(device_type_id, sort_order) where is_active;

create table if not exists public.device_fields (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  key text not null check (key ~ '^[a-z][a-z0-9_]{1,60}$'),
  label text not null check (char_length(trim(label)) between 2 and 120),
  field_type text not null check (field_type in ('TEXT','NUMBER','TEXTAREA','SELECT','MULTISELECT','CHECKBOX','RADIO','SWITCH','REPEATABLE')),
  data_source_key text check (data_source_key is null or data_source_key in ('brand','family','model','variant','color','memory_capacity','storage_capacity','operating_system','mobile_operator','accessory','lock_type')),
  placeholder text,
  help_text text,
  validation jsonb not null default '{}'::jsonb check (jsonb_typeof(validation) = 'object'),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists device_fields_global_key_unique on public.device_fields(key) where organization_id is null;
create unique index if not exists device_fields_org_key_unique on public.device_fields(organization_id, key) where organization_id is not null;

create table if not exists public.device_type_fields (
  id uuid primary key default gen_random_uuid(),
  device_type_id uuid not null references public.device_types(id) on delete restrict,
  section_id uuid not null references public.device_form_sections(id) on delete restrict,
  field_id uuid not null references public.device_fields(id) on delete restrict,
  sort_order integer not null default 0,
  required boolean not null default false,
  overrides jsonb not null default '{}'::jsonb check (jsonb_typeof(overrides) = 'object'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (device_type_id, section_id, field_id)
);
create index if not exists device_type_fields_type_section_idx on public.device_type_fields(device_type_id, section_id, sort_order) where is_active;
create index if not exists device_type_fields_field_idx on public.device_type_fields(field_id);

create table if not exists public.device_field_options (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  field_id uuid not null references public.device_fields(id) on delete restrict,
  value text not null check (char_length(trim(value)) between 1 and 160),
  label text not null check (char_length(trim(label)) between 1 and 160),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists device_field_options_global_unique on public.device_field_options(field_id, lower(regexp_replace(trim(value), '\s+', ' ', 'g'))) where organization_id is null;
create unique index if not exists device_field_options_org_unique on public.device_field_options(organization_id, field_id, lower(regexp_replace(trim(value), '\s+', ' ', 'g'))) where organization_id is not null;
create index if not exists device_field_options_field_idx on public.device_field_options(field_id, sort_order) where is_active;

create table if not exists public.device_field_dependencies (
  id uuid primary key default gen_random_uuid(),
  device_type_field_id uuid not null references public.device_type_fields(id) on delete cascade,
  parent_device_type_field_id uuid not null references public.device_type_fields(id) on delete cascade,
  operator text not null default 'EQUALS' check (operator in ('EQUALS','NOT_EQUALS','IN','NOT_EMPTY','EMPTY')),
  expected_value jsonb,
  created_at timestamptz not null default now(),
  check (device_type_field_id <> parent_device_type_field_id)
);
create index if not exists device_field_dependencies_child_idx on public.device_field_dependencies(device_type_field_id);
create index if not exists device_field_dependencies_parent_idx on public.device_field_dependencies(parent_device_type_field_id);

-- Catálogos estructurales: no son opciones EAV del formulario.
create table if not exists public.device_product_families (
  id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade,
  brand_id uuid not null references public.device_brands(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 120), code text,
  is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create unique index if not exists device_product_families_global_unique on public.device_product_families(brand_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is null;
create unique index if not exists device_product_families_org_unique on public.device_product_families(organization_id, brand_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is not null;
create index if not exists device_product_families_brand_idx on public.device_product_families(brand_id, name) where is_active;

alter table public.device_models add column if not exists family_id uuid references public.device_product_families(id) on delete set null;
alter table public.device_models add column if not exists technical_code text;
create index if not exists device_models_family_idx on public.device_models(family_id) where is_active;

create table if not exists public.device_model_variants (
  id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade,
  model_id uuid not null references public.device_models(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 140), technical_code text,
  is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create unique index if not exists device_model_variants_global_unique on public.device_model_variants(model_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is null;
create unique index if not exists device_model_variants_org_unique on public.device_model_variants(organization_id, model_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is not null;
create index if not exists device_model_variants_model_idx on public.device_model_variants(model_id, name) where is_active;

create table if not exists public.memory_capacities (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, capacity_mb integer, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists memory_capacities_global_unique on public.memory_capacities(lower(name)) where organization_id is null;
create unique index if not exists memory_capacities_org_unique on public.memory_capacities(organization_id, lower(name)) where organization_id is not null;
create table if not exists public.storage_capacities (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, capacity_gb integer, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists storage_capacities_global_unique on public.storage_capacities(lower(name)) where organization_id is null;
create unique index if not exists storage_capacities_org_unique on public.storage_capacities(organization_id, lower(name)) where organization_id is not null;
create table if not exists public.operating_systems (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, platform text, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists operating_systems_global_unique on public.operating_systems(lower(name)) where organization_id is null;
create unique index if not exists operating_systems_org_unique on public.operating_systems(organization_id, lower(name)) where organization_id is not null;
create table if not exists public.mobile_operators (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, country_code text not null default 'AR', is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists mobile_operators_global_unique on public.mobile_operators(lower(name), country_code) where organization_id is null;
create unique index if not exists mobile_operators_org_unique on public.mobile_operators(organization_id, lower(name), country_code) where organization_id is not null;
create table if not exists public.device_accessories (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists device_accessories_global_unique on public.device_accessories(lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is null;
create unique index if not exists device_accessories_org_unique on public.device_accessories(organization_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is not null;
create table if not exists public.device_lock_types (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists device_lock_types_global_unique on public.device_lock_types(lower(name)) where organization_id is null;
create unique index if not exists device_lock_types_org_unique on public.device_lock_types(organization_id, lower(name)) where organization_id is not null;

-- Valores configurables de una unidad: EAV sólo para propiedades de formularios,
-- nunca para los catálogos maestros o relaciones estructurales.
create table if not exists public.customer_device_field_values (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_device_id uuid not null references public.customer_devices(id) on delete cascade,
  device_type_field_id uuid not null references public.device_type_fields(id) on delete restrict,
  option_id uuid references public.device_field_options(id) on delete restrict,
  value_text text, value_number numeric, value_boolean boolean, value_json jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (num_nonnulls(value_text, value_number, value_boolean, value_json, option_id) = 1),
  unique(customer_device_id, device_type_field_id)
);
create index if not exists customer_device_field_values_device_idx on public.customer_device_field_values(organization_id, customer_device_id);
create trigger customer_device_field_values_updated_at before update on public.customer_device_field_values for each row execute function public.set_updated_at();

create table if not exists public.component_types (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, max_instances integer, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists component_types_global_unique on public.component_types(lower(name)) where organization_id is null;
create unique index if not exists component_types_org_unique on public.component_types(organization_id, lower(name)) where organization_id is not null;
create table if not exists public.component_attribute_definitions (id uuid primary key default gen_random_uuid(), component_type_id uuid not null references public.component_types(id) on delete restrict, key text not null check (key ~ '^[a-z][a-z0-9_]{1,60}$'), label text not null, field_type text not null check(field_type in ('TEXT','NUMBER','SELECT')), required boolean not null default false, sort_order integer not null default 0, is_active boolean not null default true, unique(component_type_id,key));
create table if not exists public.component_attribute_options (id uuid primary key default gen_random_uuid(), attribute_definition_id uuid not null references public.component_attribute_definitions(id) on delete cascade, value text not null, label text not null, sort_order integer not null default 0, is_active boolean not null default true, unique(attribute_definition_id, value));
create table if not exists public.repair_device_components (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, customer_device_id uuid not null references public.customer_devices(id) on delete restrict, component_type_id uuid not null references public.component_types(id) on delete restrict, sort_order integer not null default 0, created_at timestamptz not null default now());
create index if not exists repair_device_components_device_idx on public.repair_device_components(organization_id, customer_device_id, component_type_id);
create table if not exists public.repair_device_component_values (id uuid primary key default gen_random_uuid(), component_id uuid not null references public.repair_device_components(id) on delete cascade, attribute_definition_id uuid not null references public.component_attribute_definitions(id) on delete restrict, option_id uuid references public.component_attribute_options(id) on delete restrict, value_text text, unique(component_id, attribute_definition_id));

create table if not exists public.diagnostic_result_types (id uuid primary key default gen_random_uuid(), code text not null unique, label text not null, sort_order integer not null default 0, is_active boolean not null default true);
create table if not exists public.diagnostic_test_types (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, key text not null, label text not null, category text, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists diagnostic_test_types_global_key_unique on public.diagnostic_test_types(key) where organization_id is null;
create unique index if not exists diagnostic_test_types_org_key_unique on public.diagnostic_test_types(organization_id,key) where organization_id is not null;
create table if not exists public.device_type_diagnostic_tests (id uuid primary key default gen_random_uuid(), device_type_id uuid not null references public.device_types(id) on delete restrict, diagnostic_test_type_id uuid not null references public.diagnostic_test_types(id) on delete restrict, section_id uuid references public.device_form_sections(id) on delete set null, sort_order integer not null default 0, required boolean not null default false, is_active boolean not null default true, unique(device_type_id, diagnostic_test_type_id));
create index if not exists device_type_diagnostic_tests_type_idx on public.device_type_diagnostic_tests(device_type_id,sort_order) where is_active;
create table if not exists public.repair_device_diagnostics (id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade, reception_id uuid not null references public.device_receptions(id) on delete restrict, diagnostic_test_type_id uuid not null references public.diagnostic_test_types(id) on delete restrict, result_type_id uuid references public.diagnostic_result_types(id) on delete restrict, notes text, created_at timestamptz not null default now(), unique(reception_id,diagnostic_test_type_id));
create index if not exists repair_device_diagnostics_reception_idx on public.repair_device_diagnostics(organization_id,reception_id);

create table if not exists public.service_categories (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists service_categories_global_unique on public.service_categories(lower(name)) where organization_id is null;
create unique index if not exists service_categories_org_unique on public.service_categories(organization_id,lower(name)) where organization_id is not null;
create table if not exists public.technical_services (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, service_category_id uuid references public.service_categories(id) on delete set null, name text not null, description text, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create index if not exists technical_services_category_idx on public.technical_services(service_category_id,name) where is_active;
create table if not exists public.device_type_services (device_type_id uuid not null references public.device_types(id) on delete restrict, technical_service_id uuid not null references public.technical_services(id) on delete restrict, sort_order integer not null default 0, is_active boolean not null default true, primary key(device_type_id,technical_service_id));
create table if not exists public.reception_evidence_types (id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade, name text not null, is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now());
create unique index if not exists reception_evidence_types_global_unique on public.reception_evidence_types(lower(name)) where organization_id is null;
create unique index if not exists reception_evidence_types_org_unique on public.reception_evidence_types(organization_id,lower(name)) where organization_id is not null;

-- Nuevas relaciones de customer_devices; los campos de texto legacy se mantienen para compatibilidad y snapshot.
alter table public.customer_devices add column if not exists family_id uuid references public.device_product_families(id) on delete set null;
alter table public.customer_devices add column if not exists variant_id uuid references public.device_model_variants(id) on delete set null;
alter table public.customer_devices add column if not exists color_id uuid references public.device_colors(id) on delete set null;
alter table public.customer_devices add column if not exists operating_system_id uuid references public.operating_systems(id) on delete set null;
alter table public.customer_devices add column if not exists mobile_operator_id uuid references public.mobile_operators(id) on delete set null;
alter table public.customer_devices add column if not exists is_locked boolean not null default false;
alter table public.customer_devices add column if not exists lock_type_id uuid references public.device_lock_types(id) on delete set null;
create index if not exists customer_devices_model_idx on public.customer_devices(organization_id,model_id);
create index if not exists customer_devices_family_idx on public.customer_devices(organization_id,family_id);

-- Datos base. Se cargan por migración y después el formulario sólo los consulta.
insert into public.memory_capacities(name, capacity_mb) select x, mb from (values ('1 GB',1024),('2 GB',2048),('3 GB',3072),('4 GB',4096),('6 GB',6144),('8 GB',8192),('12 GB',12288),('16 GB',16384),('24 GB',24576),('32 GB',32768),('64 GB',65536)) as s(x,mb) on conflict do nothing;
insert into public.storage_capacities(name, capacity_gb) select x, gb from (values ('8 GB',8),('16 GB',16),('32 GB',32),('64 GB',64),('128 GB',128),('256 GB',256),('512 GB',512),('1 TB',1024),('2 TB',2048)) as s(x,gb) on conflict do nothing;
insert into public.operating_systems(name,platform) values ('Android','MOBILE'),('iOS','MOBILE'),('Windows','DESKTOP'),('Linux','DESKTOP'),('macOS','DESKTOP') on conflict do nothing;
insert into public.mobile_operators(name,country_code) values ('Personal','AR'),('Claro','AR'),('Movistar','AR'),('Tuenti','AR') on conflict do nothing;
insert into public.device_accessories(name) values ('Cargador'),('Fuente'),('Cable USB'),('Cable USB-C'),('Cable Lightning'),('Cable HDMI'),('Funda'),('Bolso'),('Caja'),('Batería'),('Mouse'),('Teclado'),('Adaptador'),('Pendrive'),('Memoria SD'),('Stylus'),('Control remoto'),('Base'),('Auriculares') on conflict do nothing;
insert into public.device_lock_types(name) values ('PIN'),('Patrón'),('Contraseña'),('Biometría'),('Bloqueo de cuenta') on conflict do nothing;
insert into public.diagnostic_result_types(code,label,sort_order) values ('OK','Correcto',1),('FAIL','Falla',2),('PARTIAL','Parcial',3),('INTERMITTENT','Intermitente',4),('NOT_TESTABLE','No comprobable',5),('NOT_APPLICABLE','No aplica',6) on conflict(code) do update set label=excluded.label,sort_order=excluded.sort_order;

-- Campos reutilizables y opciones simples. data_source_key resuelve tablas en servidor.
insert into public.device_fields(key,label,field_type,data_source_key,placeholder,help_text,validation) values
 ('variant','Variante / código','SELECT','variant','Buscar variante','Opcional; por ejemplo SM-A546E o CUH-2215B','{}'),
 ('year','Año','NUMBER',null,'Ej. 2024',null,'{"min_value":1980,"max_value":2100}'),
 ('serial_number','Número de serie','TEXT',null,null,null,'{"max_length":120}'),
 ('imei_1','IMEI 1','TEXT',null,null,null,'{"max_length":20,"regex_pattern":"^[0-9]*$"}'),
 ('imei_2','IMEI 2','TEXT',null,null,null,'{"max_length":20,"regex_pattern":"^[0-9]*$"}'),
 ('memory_capacity','RAM','SELECT','memory_capacity','Seleccionar memoria',null,'{}'),
 ('storage_capacity','Almacenamiento','SELECT','storage_capacity','Seleccionar capacidad',null,'{}'),
 ('operating_system','Sistema operativo','SELECT','operating_system','Seleccionar sistema',null,'{}'),
 ('mobile_operator','Operador','SELECT','mobile_operator','Seleccionar operador',null,'{}'),
 ('is_locked','¿Tiene bloqueo?','SWITCH',null,null,'Nodo no almacena PIN, contraseña ni patrón.','{}'),
 ('lock_type','Tipo de bloqueo','SELECT','lock_type','Seleccionar tipo',null,'{}'),
 ('motherboard','Motherboard','TEXT',null,'Ingresá motherboard',null,'{"max_length":160}'),
 ('processor','Procesador','TEXT',null,'Ingresá procesador',null,'{"max_length":160}'),
 ('gpu','GPU / Placa de vídeo','TEXT',null,'Modelo y VRAM','Ingresá el modelo de tu placa de vídeo junto con la cantidad de memoria VRAM que contiene.','{"max_length":160}'),
 ('screen_size','Tamaño de pantalla','TEXT',null,'Ej. 24 pulgadas',null,'{"max_length":60}'),
 ('resolution','Resolución','SELECT',null,'Seleccionar resolución',null,'{}'),
 ('technology','Tecnología','SELECT',null,'Seleccionar tecnología',null,'{}'),
 ('connectivity','Conectividad','SELECT',null,'Seleccionar conectividad',null,'{}')
on conflict do nothing;

-- Opciones configurables (no catálogos estructurales).
insert into public.device_field_options(field_id,value,label,sort_order)
select f.id,s.value,s.label,s.sort_order from public.device_fields f cross join (values
 ('resolution','HD','HD',1),('resolution','FULL_HD','Full HD',2),('resolution','2K','2K',3),('resolution','4K','4K',4),('resolution','8K','8K',5),
 ('technology','INK','Tinta',1),('technology','LASER','Láser',2),('technology','THERMAL','Térmica',3),('technology','OTHER','Otra',4),
 ('connectivity','USB','USB',1),('connectivity','WIFI','Wi‑Fi',2),('connectivity','ETHERNET','Ethernet',3),('connectivity','BLUETOOTH','Bluetooth',4),('connectivity','HDMI','HDMI',5),('connectivity','DISPLAYPORT','DisplayPort',6),('connectivity','VGA','VGA',7),('connectivity','USB_C','USB‑C',8)
) as s(field_key,value,label,sort_order) where f.organization_id is null and f.key=s.field_key on conflict do nothing;

-- Formularios iniciales: teléfono/celular y PC de escritorio. Otros tipos pueden
-- administrarse sin agregar condicionales React mediante Tablas maestras.
with form_seeds(type_name,section_key,section_title,sort_order) as (values
 ('Teléfono / Celular','identification','Identificación',10),('Teléfono / Celular','security','Seguridad',20),
 ('PC de escritorio','identification','Identificación',10),('PC de escritorio','hardware','Hardware',20)
)
insert into public.device_form_sections(device_type_id,key,title,sort_order)
select t.id,s.section_key,s.section_title,s.sort_order from form_seeds s join public.device_types t on t.organization_id is null and t.name=s.type_name on conflict do nothing;

with assignments(type_name,section_key,field_key,sort_order,required) as (values
 ('Teléfono / Celular','identification','variant',10,false),('Teléfono / Celular','identification','imei_1',20,false),('Teléfono / Celular','identification','imei_2',30,false),('Teléfono / Celular','identification','memory_capacity',40,false),('Teléfono / Celular','identification','storage_capacity',50,false),('Teléfono / Celular','identification','operating_system',60,false),('Teléfono / Celular','identification','mobile_operator',70,false),('Teléfono / Celular','security','is_locked',10,false),('Teléfono / Celular','security','lock_type',20,false),
 ('PC de escritorio','identification','variant',10,false),('PC de escritorio','identification','operating_system',20,false),('PC de escritorio','hardware','motherboard',10,false),('PC de escritorio','hardware','processor',20,false),('PC de escritorio','hardware','gpu',30,false)
)
insert into public.device_type_fields(device_type_id,section_id,field_id,sort_order,required)
select t.id,s.id,f.id,a.sort_order,a.required from assignments a join public.device_types t on t.organization_id is null and t.name=a.type_name join public.device_form_sections s on s.device_type_id=t.id and s.organization_id is null and s.key=a.section_key join public.device_fields f on f.organization_id is null and f.key=a.field_key on conflict do nothing;

insert into public.device_field_dependencies(device_type_field_id,parent_device_type_field_id,operator,expected_value)
select child.id,parent.id,'EQUALS','true'::jsonb from public.device_type_fields child join public.device_fields child_field on child_field.id=child.field_id and child_field.key='lock_type' join public.device_type_fields parent on parent.device_type_id=child.device_type_id join public.device_fields parent_field on parent_field.id=parent.field_id and parent_field.key='is_locked' on conflict do nothing;

-- RLS: el catálogo permite leer global + propio. Las escrituras se realizan por
-- RPC autorizada; no se concede INSERT/UPDATE/DELETE directo al cliente.
alter table public.device_form_sections enable row level security;
alter table public.device_fields enable row level security;
alter table public.device_type_fields enable row level security;
alter table public.device_field_options enable row level security;
alter table public.device_field_dependencies enable row level security;
alter table public.device_product_families enable row level security;
alter table public.device_model_variants enable row level security;
alter table public.memory_capacities enable row level security;
alter table public.storage_capacities enable row level security;
alter table public.operating_systems enable row level security;
alter table public.mobile_operators enable row level security;
alter table public.device_accessories enable row level security;
alter table public.device_lock_types enable row level security;
alter table public.customer_device_field_values enable row level security;
alter table public.component_types enable row level security;
alter table public.component_attribute_definitions enable row level security;
alter table public.component_attribute_options enable row level security;
alter table public.repair_device_components enable row level security;
alter table public.repair_device_component_values enable row level security;
alter table public.diagnostic_result_types enable row level security;
alter table public.diagnostic_test_types enable row level security;
alter table public.device_type_diagnostic_tests enable row level security;
alter table public.repair_device_diagnostics enable row level security;
alter table public.service_categories enable row level security;
alter table public.technical_services enable row level security;
alter table public.device_type_services enable row level security;
alter table public.reception_evidence_types enable row level security;

create policy device_form_sections_read on public.device_form_sections for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_fields_read on public.device_fields for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_type_fields_read on public.device_type_fields for select to authenticated using (exists(select 1 from public.device_types t where t.id=device_type_fields.device_type_id and (t.organization_id is null or t.organization_id=public.current_organization_id())));
create policy device_field_options_read on public.device_field_options for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_field_dependencies_read on public.device_field_dependencies for select to authenticated using (true);
create policy device_product_families_read on public.device_product_families for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_model_variants_read on public.device_model_variants for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy memory_capacities_read on public.memory_capacities for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy storage_capacities_read on public.storage_capacities for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy operating_systems_read on public.operating_systems for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy mobile_operators_read on public.mobile_operators for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_accessories_read on public.device_accessories for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_lock_types_read on public.device_lock_types for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy customer_device_field_values_read on public.customer_device_field_values for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
create policy component_types_read on public.component_types for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy component_attribute_definitions_read on public.component_attribute_definitions for select to authenticated using (true);
create policy component_attribute_options_read on public.component_attribute_options for select to authenticated using (true);
create policy repair_device_components_read on public.repair_device_components for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
create policy repair_device_component_values_read on public.repair_device_component_values for select to authenticated using (exists(select 1 from public.repair_device_components c where c.id=repair_device_component_values.component_id and c.organization_id=public.current_organization_id()));
create policy diagnostic_result_types_read on public.diagnostic_result_types for select to authenticated using (true);
create policy diagnostic_test_types_read on public.diagnostic_test_types for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_type_diagnostic_tests_read on public.device_type_diagnostic_tests for select to authenticated using (true);
create policy repair_device_diagnostics_read on public.repair_device_diagnostics for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
create policy service_categories_read on public.service_categories for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy technical_services_read on public.technical_services for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_type_services_read on public.device_type_services for select to authenticated using (true);
create policy reception_evidence_types_read on public.reception_evidence_types for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());

grant select on public.device_form_sections,public.device_fields,public.device_type_fields,public.device_field_options,public.device_field_dependencies,public.device_product_families,public.device_model_variants,public.memory_capacities,public.storage_capacities,public.operating_systems,public.mobile_operators,public.device_accessories,public.device_lock_types,public.customer_device_field_values,public.component_types,public.component_attribute_definitions,public.component_attribute_options,public.repair_device_components,public.repair_device_component_values,public.diagnostic_result_types,public.diagnostic_test_types,public.device_type_diagnostic_tests,public.repair_device_diagnostics,public.service_categories,public.technical_services,public.device_type_services,public.reception_evidence_types to authenticated;

-- Persistencia transaccional de datos configurables. El cliente sólo envía
-- claves/valores; el servidor verifica que cada clave pertenezca al tipo.
create or replace function public.create_customer_device_dynamic(
  p_customer_id uuid, p_type_id uuid, p_brand_id uuid, p_model_id uuid,
  p_model text, p_year text, p_color text, p_serial_number text,
  p_imei_1 text, p_imei_2 text, p_attributes jsonb, p_memories jsonb,
  p_storage_units jsonb, p_accessories text[]
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_org uuid:=public.assert_reception_owner(); v_device_id uuid; v_model text:=regexp_replace(trim(p_model),'\s+',' ','g');
  v_item record; v_field record; v_text text; v_option uuid;
begin
  perform 1 from public.customers where id=p_customer_id and organization_id=v_org;
  if not found then raise exception 'INVALID_CUSTOMER'; end if;
  perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org);
  if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
  perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org);
  if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if char_length(v_model) not between 2 and 120 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_model_id is not null then
    perform 1 from public.device_models where id=p_model_id and device_type_id=p_type_id and brand_id=p_brand_id and is_active and (organization_id is null or organization_id=v_org);
    if not found then raise exception 'INVALID_DEVICE_MODEL'; end if;
  end if;
  if jsonb_typeof(coalesce(p_attributes,'{}'::jsonb)) <> 'object' then raise exception 'INVALID_DEVICE_FIELDS'; end if;
  for v_field in
    select tf.id, f.key, tf.required from public.device_type_fields tf
    join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and tf.required
  loop
    if nullif(trim(coalesce(p_attributes->>v_field.key,'')),'') is null then
      raise exception 'REQUIRED_DEVICE_FIELD';
    end if;
  end loop;
  for v_item in select key,value from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) loop
    select tf.id, f.id as field_id, f.field_type, f.data_source_key, tf.required
    into v_field from public.device_type_fields tf join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and f.key=v_item.key
    limit 1;
    if v_field.id is null then raise exception 'INVALID_DEVICE_FIELD'; end if;
    v_text:=nullif(regexp_replace(trim(coalesce(v_item.value #>> '{}','')),'\s+',' ','g'),'');
    if v_field.required and v_text is null then raise exception 'REQUIRED_DEVICE_FIELD'; end if;
  end loop;
  insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
  values(v_org,p_customer_id,p_type_id,p_brand_id,p_model_id,v_model,nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),coalesce(nullif(trim(p_imei_1),''),nullif(p_attributes->>'imei_1','')),coalesce(nullif(trim(p_imei_2),''),nullif(p_attributes->>'imei_2','')),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_device_id;
  for v_item in select key,value from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) loop
    select tf.id, f.id as field_id, f.field_type, f.data_source_key into v_field
    from public.device_type_fields tf join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and f.key=v_item.key limit 1;
    v_text:=nullif(regexp_replace(trim(coalesce(v_item.value #>> '{}','')),'\s+',' ','g'),'');
    if v_text is null then continue; end if;
    v_option:=null;
    if v_field.data_source_key is null and v_field.field_type in ('SELECT','RADIO') then
      select id into v_option from public.device_field_options where field_id=v_field.field_id and is_active and value=v_text and (organization_id is null or organization_id=v_org) order by organization_id nulls first limit 1;
      if v_option is null then raise exception 'INVALID_DEVICE_FIELD_OPTION'; end if;
    end if;
    insert into public.customer_device_field_values(organization_id,customer_device_id,device_type_field_id,option_id,value_text,value_boolean)
    values(v_org,v_device_id,v_field.id,v_option,case when v_option is null and v_field.field_type not in ('SWITCH','CHECKBOX') then v_text else null end,case when v_field.field_type in ('SWITCH','CHECKBOX') then (v_text='true') else null end)
    on conflict(customer_device_id,device_type_field_id) do update set option_id=excluded.option_id,value_text=excluded.value_text,value_boolean=excluded.value_boolean,updated_at=now();
  end loop;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_device_id,jsonb_build_object('customer_id',p_customer_id,'model_id',p_model_id,'dynamic_form',true));
  return v_device_id;
end; $$;
revoke all on function public.create_customer_device_dynamic(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) from public,anon;
grant execute on function public.create_customer_device_dynamic(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) to authenticated;

comment on table public.device_fields is 'Definición reutilizable de controles dinámicos. Los data_source_key se resuelven con código seguro en servidor; nunca contienen SQL.';
comment on table public.customer_device_field_values is 'Valores configurables de un dispositivo. Los catálogos maestros se conservan en tablas normalizadas.';
