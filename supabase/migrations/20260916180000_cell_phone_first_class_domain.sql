begin;

create or replace function public.is_valid_imei(p_imei text)
returns boolean language sql immutable strict set search_path='' as $$
  select p_imei ~ '^[0-9]{15}$' and (
    select sum(case when position % 2 = 0 then ((digit * 2) / 10) + ((digit * 2) % 10) else digit end) % 10 = 0
    from (
      select position, substring(p_imei from position for 1)::integer digit
      from generate_series(1,15) position
    ) digits
  )
$$;

create table public.customer_device_imeis (
  id uuid primary key default gen_random_uuid(),
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  fk_customer_device_id uuid not null references public.customer_devices(id) on delete cascade,
  imei text not null,
  position smallint not null check(position between 1 and 99),
  created_at timestamptz not null default now(),
  constraint ck_customer_device_imeis_format check(public.is_valid_imei(imei)),
  constraint uq_customer_device_imeis_device_position unique(fk_customer_device_id,position),
  constraint uq_customer_device_imeis_device_value unique(fk_customer_device_id,imei),
  constraint uq_customer_device_imeis_organization_value unique(fk_organizacion_id,imei)
);
create index ix_customer_device_imeis_device on public.customer_device_imeis(fk_customer_device_id);
alter table public.customer_device_imeis enable row level security;
revoke all on public.customer_device_imeis from anon,authenticated;
grant select on public.customer_device_imeis to authenticated;
create policy customer_device_imeis_read on public.customer_device_imeis for select to authenticated
using(fk_organizacion_id=public.current_organization_id());

create table public.customer_device_mobile_specs (
  fk_customer_device_id uuid primary key references public.customer_devices(id) on delete cascade,
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  ram_mb integer check(ram_mb is null or ram_mb between 128 and 262144),
  internal_storage_gb integer check(internal_storage_gb is null or internal_storage_gb between 1 and 16384),
  sd_card_present boolean not null default false,
  sd_card_capacity_gb integer check(sd_card_capacity_gb is null or sd_card_capacity_gb between 1 and 4096),
  updated_at timestamptz not null default now(),
  constraint ck_mobile_specs_sd_capacity check(sd_card_present or sd_card_capacity_gb is null)
);
alter table public.customer_device_mobile_specs enable row level security;
revoke all on public.customer_device_mobile_specs from anon,authenticated;
grant select on public.customer_device_mobile_specs to authenticated;
create policy customer_device_mobile_specs_read on public.customer_device_mobile_specs for select to authenticated
using(fk_organizacion_id=public.current_organization_id());

alter table public.device_receptions
  add column if not exists power_state text,
  add column if not exists image_state text,
  add column if not exists charge_state text,
  add column if not exists access_available boolean,
  add column if not exists access_method text,
  add column if not exists credential_provided boolean not null default false;
alter table public.device_receptions add constraint ck_device_receptions_power_state check(power_state is null or power_state in('POWERS_ON','DOES_NOT_POWER_ON','NOT_TESTED'));
alter table public.device_receptions add constraint ck_device_receptions_image_state check(image_state is null or image_state in('HAS_IMAGE','NO_IMAGE','NOT_TESTED','NOT_APPLICABLE'));
alter table public.device_receptions add constraint ck_device_receptions_charge_state check(charge_state is null or charge_state in('CHARGES','INTERMITTENT','DOES_NOT_CHARGE','NOT_TESTED'));
alter table public.device_receptions add constraint ck_device_receptions_access_method check(access_method is null or access_method in('UNLOCKED','PIN','PATTERN','PASSWORD','BIOMETRIC','OTHER'));
alter table public.device_receptions add constraint ck_device_receptions_access_consistency check(
  access_available is distinct from false or (access_method is null and credential_provided=false)
);

-- Cuatro marcas prioritarias sin duplicar la entidad global.
with desired(name) as (values('Samsung'),('Apple'),('Xiaomi'),('Motorola')),
cell as (select id from public.device_types where code='cell_phone')
insert into public.device_type_brands(fk_tipo_dispositivo_id,fk_marca_dispositivo_id)
select cell.id,brand.id from cell cross join desired join public.device_brands brand
  on brand.fk_organizacion_id is null and brand.normalized_name=public.normalizar_nombre_catalogo(desired.name)
on conflict do nothing;

-- Familias comerciales solicitadas. Redmi y POCO se conservan bajo Xiaomi en este seed.
with lists(brand_name,models) as (values
('Samsung',$$Galaxy A05|Galaxy A05s|Galaxy A06|Galaxy A13|Galaxy A14|Galaxy A14 5G|Galaxy A15|Galaxy A15 5G|Galaxy A16|Galaxy A16 5G|Galaxy A23|Galaxy A24|Galaxy A25 5G|Galaxy A26 5G|Galaxy A32|Galaxy A32 5G|Galaxy A33 5G|Galaxy A34 5G|Galaxy A35 5G|Galaxy A36 5G|Galaxy A52|Galaxy A52s 5G|Galaxy A53 5G|Galaxy A54 5G|Galaxy A55 5G|Galaxy A56 5G|Galaxy A72|Galaxy A73 5G|Galaxy S20|Galaxy S20+|Galaxy S20 Ultra|Galaxy S20 FE|Galaxy S21|Galaxy S21+|Galaxy S21 Ultra|Galaxy S21 FE|Galaxy S22|Galaxy S22+|Galaxy S22 Ultra|Galaxy S23|Galaxy S23+|Galaxy S23 Ultra|Galaxy S23 FE|Galaxy S24|Galaxy S24+|Galaxy S24 Ultra|Galaxy S24 FE|Galaxy S25|Galaxy S25+|Galaxy S25 Ultra$$),
('Apple',$$iPhone 6|iPhone 6 Plus|iPhone 6s|iPhone 6s Plus|iPhone SE (1st generation)|iPhone 7|iPhone 7 Plus|iPhone 8|iPhone 8 Plus|iPhone X|iPhone XR|iPhone XS|iPhone XS Max|iPhone 11|iPhone 11 Pro|iPhone 11 Pro Max|iPhone SE (2nd generation)|iPhone 12 mini|iPhone 12|iPhone 12 Pro|iPhone 12 Pro Max|iPhone 13 mini|iPhone 13|iPhone 13 Pro|iPhone 13 Pro Max|iPhone SE (3rd generation)|iPhone 14|iPhone 14 Plus|iPhone 14 Pro|iPhone 14 Pro Max|iPhone 15|iPhone 15 Plus|iPhone 15 Pro|iPhone 15 Pro Max|iPhone 16|iPhone 16 Plus|iPhone 16 Pro|iPhone 16 Pro Max|iPhone 16e|iPhone 17|iPhone Air|iPhone 17 Pro|iPhone 17 Pro Max$$),
('Xiaomi',$$Redmi 9|Redmi 9A|Redmi 9C|Redmi 9T|Redmi 10|Redmi 10C|Redmi 12|Redmi 12C|Redmi 13|Redmi 13C|Redmi 14C|Redmi Note 9|Redmi Note 9S|Redmi Note 9 Pro|Redmi Note 10|Redmi Note 10S|Redmi Note 10 Pro|Redmi Note 11|Redmi Note 11S|Redmi Note 11 Pro|Redmi Note 12|Redmi Note 12 5G|Redmi Note 12 Pro 5G|Redmi Note 13|Redmi Note 13 5G|Redmi Note 13 Pro|Redmi Note 13 Pro 5G|Redmi Note 13 Pro+ 5G|Redmi Note 14|Redmi Note 14 5G|Redmi Note 14 Pro|Redmi Note 14 Pro 5G|Redmi Note 14 Pro+ 5G|Xiaomi 11 Lite 5G NE|Xiaomi 12|Xiaomi 12 Lite|Xiaomi 12T|Xiaomi 12T Pro|Xiaomi 13|Xiaomi 13 Lite|Xiaomi 13T|Xiaomi 13T Pro|Xiaomi 14|Xiaomi 14T|Xiaomi 14T Pro|POCO X5 5G|POCO X6 5G|POCO X6 Pro 5G|POCO C65|POCO C75$$),
('Motorola',$$Moto E6 Plus|Moto E7|Moto E7 Plus|Moto E7 Power|Moto E13|Moto E14|Moto E20|Moto E22|Moto E22i|Moto E32|Moto E32s|Moto E40|Moto G8|Moto G8 Power|Moto G9 Play|Moto G9 Plus|Moto G9 Power|Moto G20|Moto G22|Moto G23|Moto G24|Moto G24 Power|Moto G30|Moto G31|Moto G32|Moto G34 5G|Moto G35 5G|Moto G41|Moto G42|Moto G50 5G|Moto G51 5G|Moto G52|Moto G53 5G|Moto G54 5G|Moto G55 5G|Moto G60|Moto G60s|Moto G71 5G|Moto G72|Moto G73 5G|Moto G75 5G|Moto G84 5G|Moto G85 5G|Moto Edge 20|Moto Edge 30|Motorola Edge 40|Motorola Edge 40 Neo|Motorola Edge 50 Fusion|Motorola Edge 50 Pro|Motorola Edge 50 Ultra$$)
), source as (
  select brand_name,btrim(model_name) model_name from lists cross join lateral regexp_split_to_table(models,'\|') model_name
), cell as(select id from public.device_types where code='cell_phone')
insert into public.device_models(fk_tipo_dispositivo_id,fk_marca_dispositivo_id,name,alcance,fk_organizacion_id,is_active)
select cell.id,brand.id,source.model_name,'GLOBAL',null,true
from source cross join cell join public.device_brands brand
  on brand.fk_organizacion_id is null and brand.normalized_name=public.normalizar_nombre_catalogo(source.brand_name)
on conflict on constraint uq_modelos_dispositivo_nombre_alcance do update set is_active=true,updated_at=now();

-- Configuración data-driven de Celular.
insert into public.device_form_sections(key,title,description,alcance,fk_organizacion_id,sort_order,ui_config,is_active)
select source.key,source.title,source.description,'GLOBAL',null,source.sort_order,'{"columns":{"base":1,"md":2},"gap":"md"}'::jsonb,true
from (values
 ('mobile_specs','Especificaciones','Datos permanentes conocidos del celular.',10),
 ('mobile_identifiers','Identificadores','IMEI y datos de identificación técnica.',20)
)source(key,title,description,sort_order)
on conflict(key,fk_organizacion_id) do update set title=excluded.title,description=excluded.description,sort_order=excluded.sort_order,is_active=true;

insert into public.device_fields(key,label,field_type,data_source_key,placeholder,help_text,validation,alcance,is_active) values
 ('mobile_ram_mb','RAM','SELECT',null,'Seleccionar RAM','Opcional si no puede comprobarse.','{}','GLOBAL',true),
 ('mobile_storage_gb','Almacenamiento interno','SELECT',null,'Seleccionar almacenamiento','Opcional si no puede comprobarse.','{}','GLOBAL',true),
 ('mobile_sd_present','Tarjeta microSD presente','SWITCH',null,null,null,'{}','GLOBAL',true),
 ('mobile_sd_capacity_gb','Capacidad microSD','SELECT',null,'Seleccionar capacidad',null,'{}','GLOBAL',true),
 ('mobile_imeis','IMEI','REPEATABLE',null,null,'Opcional. Sólo se guardan IMEI válidos; nunca texto libre.','{}','GLOBAL',true)
on conflict(key,fk_organizacion_id) do update set label=excluded.label,field_type=excluded.field_type,help_text=excluded.help_text,is_active=true;

with options(field_key,value,label,sort_order) as(values
 ('mobile_ram_mb','2048','2 GB',10),('mobile_ram_mb','3072','3 GB',20),('mobile_ram_mb','4096','4 GB',30),('mobile_ram_mb','6144','6 GB',40),('mobile_ram_mb','8192','8 GB',50),('mobile_ram_mb','12288','12 GB',60),('mobile_ram_mb','16384','16 GB',70),
 ('mobile_storage_gb','16','16 GB',10),('mobile_storage_gb','32','32 GB',20),('mobile_storage_gb','64','64 GB',30),('mobile_storage_gb','128','128 GB',40),('mobile_storage_gb','256','256 GB',50),('mobile_storage_gb','512','512 GB',60),('mobile_storage_gb','1024','1 TB',70),
 ('mobile_sd_capacity_gb','8','8 GB',10),('mobile_sd_capacity_gb','16','16 GB',20),('mobile_sd_capacity_gb','32','32 GB',30),('mobile_sd_capacity_gb','64','64 GB',40),('mobile_sd_capacity_gb','128','128 GB',50),('mobile_sd_capacity_gb','256','256 GB',60),('mobile_sd_capacity_gb','512','512 GB',70),('mobile_sd_capacity_gb','1024','1 TB',80)
)
insert into public.device_field_options(fk_campo_dispositivo_id,value,label,sort_order,is_active)
select field.id,options.value,options.label,options.sort_order,true from options join public.device_fields field on field.key=options.field_key and field.fk_organizacion_id is null
on conflict(fk_campo_dispositivo_id,value) do update set label=excluded.label,sort_order=excluded.sort_order,is_active=true;

with assignment(section_key,field_key,sort_order) as(values
 ('mobile_specs','mobile_ram_mb',10),('mobile_specs','mobile_storage_gb',20),('mobile_specs','mobile_sd_present',30),('mobile_specs','mobile_sd_capacity_gb',40),('mobile_identifiers','mobile_imeis',10)
)
insert into public.device_type_fields(fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,sort_order,required,overrides,is_active)
select type.id,section.id,field.id,assignment.sort_order,false,
  case when assignment.field_key='mobile_imeis' then '{"component":"mobile-imeis","fullWidth":true}'::jsonb else '{}'::jsonb end,true
from assignment join public.device_types type on type.code='cell_phone'
join public.device_form_sections section on section.key=assignment.section_key and section.fk_organizacion_id is null
join public.device_fields field on field.key=assignment.field_key and field.fk_organizacion_id is null
on conflict(fk_tipo_dispositivo_id,fk_campo_dispositivo_id) do update set fk_seccion_formulario_dispositivo_id=excluded.fk_seccion_formulario_dispositivo_id,sort_order=excluded.sort_order,required=false,overrides=excluded.overrides,is_active=true;

-- Checklist funcional específico, no obligatorio.
with controls(key,label,sort_order) as(values
 ('screen_display','Pantalla / display',10),('front_glass','Vidrio',20),('touch','Táctil',30),('back_cover','Tapa trasera',40),('frame_chassis','Marco / chasis',50),('power_button','Botón de encendido',60),('volume_buttons','Botones de volumen',70),('charging_port','Puerto de carga',80),('front_camera','Cámara frontal',90),('rear_camera','Cámara trasera',100),('flash','Flash',110),('speaker','Parlante',120),('earpiece','Auricular',130),('microphone','Micrófono',140),('vibration','Vibración',150),('sim_tray','Bandeja SIM',160),('fingerprint','Lector de huella',170),('face_unlock','Reconocimiento facial / Face ID',180),('wifi','Wi-Fi',190),('bluetooth','Bluetooth',200),('mobile_signal','Red móvil / señal',210),('charging','Carga',220),('headphone_jack','Conector de auriculares',230),('micro_sd','microSD',240),('proximity_sensor','Sensor de proximidad',250),('visible_moisture','Humedad / oxidación visible',260)
), cell as(select id from public.device_types where code='cell_phone')
insert into public.device_reception_controls(key,label,is_critical,is_active)
select controls.key,controls.label,controls.key in('screen_display','visible_moisture'),true from controls
on conflict(key) do update set label=excluded.label,is_active=true;

with controls(key,sort_order) as(values
 ('screen_display',10),('front_glass',20),('touch',30),('back_cover',40),('frame_chassis',50),('power_button',60),('volume_buttons',70),('charging_port',80),('front_camera',90),('rear_camera',100),('flash',110),('speaker',120),('earpiece',130),('microphone',140),('vibration',150),('sim_tray',160),('fingerprint',170),('face_unlock',180),('wifi',190),('bluetooth',200),('mobile_signal',210),('charging',220),('headphone_jack',230),('micro_sd',240),('proximity_sensor',250),('visible_moisture',260)
)
insert into public.device_type_reception_controls(fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id,sort_order,obligatorio,is_active)
select type.id,control.id,controls.sort_order,false,true from controls
join public.device_types type on type.code='cell_phone' join public.device_reception_controls control on control.key=controls.key
on conflict(fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id) do update set sort_order=excluded.sort_order,obligatorio=false,is_active=true;

insert into public.device_accessories(nombre,alcance,fk_organizacion_id,activo)
select name,'GLOBAL',null,true from unnest(array['Cargador','Cable USB','Funda','SIM','microSD','Caja','Adaptador','Auriculares','Otro']) name
on conflict(nombre_normalizado,fk_organizacion_id) do update set activo=true;

create or replace function public.save_customer_device_step_two(
  p_customer_id uuid,p_device_type_id uuid,p_device_brand_id uuid,p_device_model_id uuid,
  p_serial_number text default null,p_observations text default null,p_customer_device_id uuid default null,
  p_attributes jsonb default '{}'::jsonb,p_ram_modules jsonb default '[]'::jsonb,
  p_storage_drives jsonb default '[]'::jsonb,p_ports jsonb default '[]'::jsonb,p_accessory_ids uuid[] default '{}'::uuid[],
  p_imeis jsonb default '[]'::jsonb,p_mobile_specs jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_device_id uuid; v_org uuid:=public.assert_reception_owner(); v_item jsonb; v_type_code text;
begin
  if jsonb_typeof(p_imeis)<>'array' or jsonb_typeof(p_mobile_specs)<>'object' then raise exception 'INVALID_MOBILE_DATA'; end if;
  v_device_id:=public.save_customer_device_step_two(
    p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,p_serial_number,p_observations,p_customer_device_id,
    p_attributes,p_ram_modules,p_storage_drives,p_ports,p_accessory_ids
  );
  select code into v_type_code from public.device_types where id=p_device_type_id;
  delete from public.customer_device_imeis where fk_customer_device_id=v_device_id;
  if v_type_code='cell_phone' then
    for v_item in select value from jsonb_array_elements(p_imeis) loop
      insert into public.customer_device_imeis(fk_organizacion_id,fk_customer_device_id,imei,position)
      values(v_org,v_device_id,regexp_replace(v_item->>'imei','[^0-9]','','g'),(v_item->>'position')::smallint);
    end loop;
    insert into public.customer_device_mobile_specs(fk_customer_device_id,fk_organizacion_id,ram_mb,internal_storage_gb,sd_card_present,sd_card_capacity_gb,updated_at)
    values(v_device_id,v_org,nullif(p_mobile_specs->>'ramMb','')::integer,nullif(p_mobile_specs->>'storageGb','')::integer,
      coalesce((p_mobile_specs->>'sdPresent')::boolean,false),nullif(p_mobile_specs->>'sdCapacityGb','')::integer,now())
    on conflict(fk_customer_device_id) do update set ram_mb=excluded.ram_mb,internal_storage_gb=excluded.internal_storage_gb,sd_card_present=excluded.sd_card_present,sd_card_capacity_gb=excluded.sd_card_capacity_gb,updated_at=now();
  elsif jsonb_array_length(p_imeis)>0 then raise exception 'IMEI_ONLY_FOR_CELL_PHONE';
  end if;
  return v_device_id;
end $$;
revoke all on function public.save_customer_device_step_two(uuid,uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb,jsonb,uuid[],jsonb,jsonb) from public,anon;
grant execute on function public.save_customer_device_step_two(uuid,uuid,uuid,uuid,text,text,uuid,jsonb,jsonb,jsonb,jsonb,uuid[],jsonb,jsonb) to authenticated;

create or replace function public.confirmar_recepcion_dispositivo(
  p_dispositivo_cliente_id uuid,p_problema_informado text,p_observaciones text,p_resultados jsonb,p_intake_metadata jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_org uuid:=public.assert_reception_owner();
begin
  if jsonb_typeof(p_intake_metadata)<>'object' then raise exception 'INVALID_INTAKE_METADATA'; end if;
  -- Nunca se aceptan secretos ni credenciales en este contrato.
  if p_intake_metadata::text ~* '(pin|password|contraseña|pattern_value|secret|credential_value)' then raise exception 'SENSITIVE_DATA_NOT_ALLOWED'; end if;
  v_id:=public.confirmar_recepcion_dispositivo(p_dispositivo_cliente_id,p_problema_informado,p_observaciones,p_resultados);
  update public.device_receptions set
    power_state=nullif(p_intake_metadata->>'powerState',''),
    image_state=nullif(p_intake_metadata->>'imageState',''),
    charge_state=nullif(p_intake_metadata->>'chargeState',''),
    access_available=nullif(p_intake_metadata->>'accessAvailable','')::boolean,
    access_method=nullif(p_intake_metadata->>'accessMethod',''),
    credential_provided=coalesce((p_intake_metadata->>'credentialProvided')::boolean,false)
  where id=v_id and fk_organizacion_id=v_org;
  return v_id;
end $$;
revoke all on function public.confirmar_recepcion_dispositivo(uuid,text,text,jsonb,jsonb) from public,anon;
grant execute on function public.confirmar_recepcion_dispositivo(uuid,text,text,jsonb,jsonb) to authenticated;

commit;
