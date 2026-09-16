begin;

alter table public.device_types add column if not exists description text;
alter table public.customer_devices add column if not exists observations text;

insert into public.device_types(name,code,description,is_active)
values
  ('Desktop PC','desktop_pc','Computadora de escritorio',true),
  ('Notebook','notebook','Computadora portátil',true),
  ('Celular','cell_phone','Teléfono celular',true)
on conflict (code) do update set name=excluded.name,description=excluded.description,is_active=true;

alter table public.component_types add column if not exists code text;
alter table public.component_types add column if not exists updated_at timestamptz not null default now();
create unique index if not exists component_types_code_unique on public.component_types(code) where code is not null;

create table if not exists public.measurement_units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  symbol text not null,
  quantity_kind text not null check(quantity_kind in ('DATA','FREQUENCY','TRANSFER_RATE','POWER','ENERGY','VOLTAGE','LENGTH')),
  is_active boolean not null default true
);

alter table public.component_attribute_definitions add column if not exists fk_default_measurement_unit_id uuid references public.measurement_units(id) on delete restrict;
create table if not exists public.device_components (
  id uuid primary key default gen_random_uuid(),
  fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict,
  fk_component_type_id uuid not null references public.component_types(id) on delete restrict,
  manufacturer text, model text, serial_number text, notes text,
  sort_order integer not null default 0 check(sort_order>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists device_components_device_idx on public.device_components(fk_customer_device_id,fk_component_type_id,sort_order);
create table if not exists public.component_specifications (
  id uuid primary key default gen_random_uuid(),
  fk_device_component_id uuid not null references public.device_components(id) on delete cascade,
  fk_component_attribute_definition_id uuid not null references public.component_attribute_definitions(id) on delete restrict,
  text_value text, numeric_value numeric, boolean_value boolean,
  fk_measurement_unit_id uuid references public.measurement_units(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(fk_device_component_id,fk_component_attribute_definition_id),
  check(num_nonnulls(text_value,numeric_value,boolean_value)=1)
);

create table if not exists public.operating_systems (
 id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade,
 name text not null, platform text, is_active boolean not null default true,
 created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create unique index if not exists operating_systems_global_unique on public.operating_systems(lower(name)) where organization_id is null;
create unique index if not exists operating_systems_org_unique on public.operating_systems(organization_id,lower(name)) where organization_id is not null;
alter table public.operating_systems add column if not exists code text;
alter table public.operating_systems add column if not exists version text;
create unique index if not exists operating_systems_code_unique on public.operating_systems(code) where code is not null;

create table if not exists public.customer_device_operating_systems (
  id uuid primary key default gen_random_uuid(),
  fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict,
  fk_operating_system_id uuid not null references public.operating_systems(id) on delete restrict,
  is_primary boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique(fk_customer_device_id,fk_operating_system_id)
);
create unique index if not exists customer_device_one_primary_os_idx on public.customer_device_operating_systems(fk_customer_device_id) where is_primary;

with seed(code,name) as (values
 ('processor','Procesador'),('ram','RAM'),('gpu','GPU'),('storage','Almacenamiento'),
 ('battery','Batería'),('screen','Pantalla'),('network_adapter','Placa de red'),
 ('touchpad','Touchpad'),('cooler','Cooler'),('motherboard','Motherboard'),('power_supply','Fuente'))
update public.component_types c set code=s.code,is_active=true,updated_at=now() from seed s
where c.organization_id is null and lower(c.name)=lower(s.name);
with seed(code,name) as (values
 ('processor','Procesador'),('ram','RAM'),('gpu','GPU'),('storage','Almacenamiento'),
 ('battery','Batería'),('screen','Pantalla'),('network_adapter','Placa de red'),
 ('touchpad','Touchpad'),('cooler','Cooler'),('motherboard','Motherboard'),('power_supply','Fuente'))
insert into public.component_types(code,name,organization_id)
select s.code,s.name,null from seed s where not exists(select 1 from public.component_types c where c.code=s.code);

insert into public.measurement_units(code,name,symbol,quantity_kind) values
 ('byte','Byte','B','DATA'),('kilobyte','Kilobyte','KB','DATA'),('megabyte','Megabyte','MB','DATA'),
 ('gigabyte','Gigabyte','GB','DATA'),('terabyte','Terabyte','TB','DATA'),
 ('megahertz','Megahertz','MHz','FREQUENCY'),('gigahertz','Gigahertz','GHz','FREQUENCY'),
 ('megatransfers_second','Megatransferencias por segundo','MT/s','TRANSFER_RATE'),
 ('watt','Watt','W','POWER'),('watt_hour','Watt hora','Wh','ENERGY'),
 ('volt','Volt','V','VOLTAGE'),('inch','Pulgada','in','LENGTH')
on conflict (code) do update set name=excluded.name,symbol=excluded.symbol,quantity_kind=excluded.quantity_kind,is_active=true;

update public.operating_systems set code=case lower(name) when 'android' then 'android' when 'ios' then 'ios' end,is_active=true
where organization_id is null and lower(name) in ('android','ios');
with seed(code,name,version,platform) as (values
 ('windows_10','Windows 10','10','DESKTOP'),('windows_11','Windows 11','11','DESKTOP'),('ubuntu_24_04','Ubuntu 24.04','24.04','DESKTOP'),
 ('debian_12','Debian 12','12','DESKTOP'),('android','Android',null,'MOBILE'),('ios','iOS',null,'MOBILE'))
insert into public.operating_systems(code,name,version,platform,organization_id)
select s.code,s.name,s.version,s.platform,null from seed s
where not exists(select 1 from public.operating_systems o where o.code=s.code);

-- Catálogos iniciales reales. Las relaciones son la única fuente usada por los selectores.
with seed(name) as (values ('Lenovo'),('HP'),('Dell'),('ASUS'),('Acer'),('Apple'),('Samsung'),('Motorola'),('Xiaomi'),('Genérica'))
insert into public.device_brands(name,alcance,fk_organizacion_id,is_active)
select s.name,'GLOBAL',null,true from seed s
where not exists(select 1 from public.device_brands b where b.normalized_name=lower(s.name) and b.fk_organizacion_id is null);

insert into public.device_type_brands(fk_tipo_dispositivo_id,fk_marca_dispositivo_id)
select t.id,b.id from public.device_types t join public.device_brands b on b.fk_organizacion_id is null
where t.code in ('desktop_pc','notebook','cell_phone') and (
 (t.code='desktop_pc' and b.name in ('Lenovo','HP','Dell','ASUS','Acer','Genérica')) or
 (t.code='notebook' and b.name in ('Lenovo','HP','Dell','ASUS','Acer','Apple')) or
 (t.code='cell_phone' and b.name in ('Apple','Samsung','Motorola','Xiaomi'))
) on conflict do nothing;

with seed(type_code,brand_name,model_name) as (values
 ('desktop_pc','Dell','OptiPlex 7090'),('desktop_pc','HP','ProDesk 400 G7'),('desktop_pc','Lenovo','ThinkCentre M70s'),('desktop_pc','ASUS','ExpertCenter D5'),
 ('notebook','Lenovo','IdeaPad 3 15ITL6'),('notebook','Dell','Latitude 5420'),('notebook','HP','250 G8'),('notebook','ASUS','VivoBook 15 X515EA'),('notebook','Acer','Aspire 5 A515-56'),
 ('cell_phone','Apple','iPhone 13'),('cell_phone','Samsung','Galaxy A14'),('cell_phone','Motorola','Moto G54 5G'),('cell_phone','Xiaomi','Redmi Note 12')
)
insert into public.device_models(fk_tipo_dispositivo_id,fk_marca_dispositivo_id,name,alcance,fk_organizacion_id,is_active)
select t.id,b.id,s.model_name,'GLOBAL',null,true from seed s
join public.device_types t on t.code=s.type_code
join public.device_brands b on b.normalized_name=lower(s.brand_name) and b.fk_organizacion_id is null
where not exists(select 1 from public.device_models m where m.fk_tipo_dispositivo_id=t.id and m.fk_marca_dispositivo_id=b.id and m.normalized_name=lower(s.model_name) and m.fk_organizacion_id is null);

alter table public.component_types enable row level security;
alter table public.measurement_units enable row level security;
alter table public.device_components enable row level security;
alter table public.component_specifications enable row level security;
alter table public.operating_systems enable row level security;
alter table public.customer_device_operating_systems enable row level security;

drop policy if exists component_types_read on public.component_types;
create policy component_types_read on public.component_types for select to authenticated using(is_active and (organization_id is null or organization_id=public.current_organization_id()));
drop policy if exists measurement_units_read on public.measurement_units;
create policy measurement_units_read on public.measurement_units for select to authenticated using(is_active);
drop policy if exists operating_systems_read on public.operating_systems;
create policy operating_systems_read on public.operating_systems for select to authenticated using(is_active and (organization_id is null or organization_id=public.current_organization_id()));
drop policy if exists device_components_tenant on public.device_components;
create policy device_components_tenant on public.device_components for all to authenticated
using(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()))
with check(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()));
drop policy if exists component_specifications_tenant on public.component_specifications;
create policy component_specifications_tenant on public.component_specifications for all to authenticated
using(exists(select 1 from public.device_components c join public.customer_devices d on d.id=c.fk_customer_device_id where c.id=fk_device_component_id and d.fk_organizacion_id=public.current_organization_id()))
with check(exists(select 1 from public.device_components c join public.customer_devices d on d.id=c.fk_customer_device_id where c.id=fk_device_component_id and d.fk_organizacion_id=public.current_organization_id()));
drop policy if exists customer_device_operating_systems_tenant on public.customer_device_operating_systems;
create policy customer_device_operating_systems_tenant on public.customer_device_operating_systems for all to authenticated
using(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()))
with check(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()));

revoke insert,update,delete on public.component_types,public.measurement_units,public.operating_systems from anon,authenticated;

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
  if char_length(coalesce(p_serial_number,''))>120 or char_length(coalesce(p_observations,''))>2000 then raise exception 'INVALID_DEVICE_DATA'; end if;
  if p_customer_device_id is null then
    insert into public.customer_devices(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,numero_serie,observations,created_by)
    values(v_org,p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,nullif(btrim(p_serial_number),''),nullif(btrim(p_observations),''),auth.uid()) returning id into v_id;
    insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata)
    values(v_org,auth.uid(),'CUSTOMER_DEVICE_CREATED','CUSTOMER_DEVICE',v_id,jsonb_build_object('customer_id',p_customer_id,'device_type_id',p_device_type_id));
  else
    update public.customer_devices set fk_tipo_dispositivo_id=p_device_type_id,fk_marca_dispositivo_id=p_device_brand_id,fk_modelo_dispositivo_id=p_device_model_id,numero_serie=nullif(btrim(p_serial_number),''),observations=nullif(btrim(p_observations),''),updated_at=now()
    where id=p_customer_device_id and fk_cliente_id=p_customer_id and fk_organizacion_id=v_org returning id into v_id;
    if v_id is null then raise exception 'INVALID_DEVICE'; end if;
    insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata)
    values(v_org,auth.uid(),'CUSTOMER_DEVICE_UPDATED','CUSTOMER_DEVICE',v_id,jsonb_build_object('device_type_id',p_device_type_id));
  end if;
  return v_id;
end $$;
revoke all on function public.save_customer_device_identification(uuid,uuid,uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.save_customer_device_identification(uuid,uuid,uuid,uuid,text,text,uuid) to authenticated;

commit;
