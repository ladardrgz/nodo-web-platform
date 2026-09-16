-- Desktop PC: identidad flexible, recepción segura e inventario histórico normalizado.
alter table public.customer_devices
  add column if not exists desktop_identity_kind text;

alter table public.customer_devices
  drop constraint if exists ck_customer_devices_desktop_identity_kind;
alter table public.customer_devices
  add constraint ck_customer_devices_desktop_identity_kind check (
    desktop_identity_kind is null or desktop_identity_kind in ('CUSTOM','OEM','UNKNOWN')
  );

comment on column public.customer_devices.desktop_identity_kind is
  'Clase de identidad exclusiva de Desktop PC: armada, OEM/prearmada o desconocida.';

alter table public.device_receptions
  add column if not exists post_state text,
  add column if not exists os_boot_state text,
  add column if not exists internal_inventory_status text,
  add column if not exists power_test_reason text;

alter table public.device_receptions
  drop constraint if exists ck_device_receptions_post_state;
alter table public.device_receptions
  add constraint ck_device_receptions_post_state check (
    post_state is null or post_state in ('COMPLETES','DOES_NOT_COMPLETE','UNDETERMINED','NOT_TESTED','NOT_APPLICABLE')
  );
alter table public.device_receptions
  drop constraint if exists ck_device_receptions_os_boot_state;
alter table public.device_receptions
  add constraint ck_device_receptions_os_boot_state check (
    os_boot_state is null or os_boot_state in ('BOOTS','DOES_NOT_BOOT','NOT_TESTED','NO_OS','NOT_APPLICABLE')
  );
alter table public.device_receptions
  drop constraint if exists ck_device_receptions_inventory_status;
alter table public.device_receptions
  add constraint ck_device_receptions_inventory_status check (
    internal_inventory_status is null or internal_inventory_status in ('COMPLETE','PARTIAL','NOT_PERFORMED')
  );
alter table public.device_receptions
  drop constraint if exists ck_device_receptions_power_test_reason;
alter table public.device_receptions
  add constraint ck_device_receptions_power_test_reason check (
    power_test_reason is null or (power_test_reason=btrim(power_test_reason) and char_length(power_test_reason) between 3 and 300)
  );

create table if not exists public.reception_accessories (
  id uuid primary key default gen_random_uuid(),
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  fk_recepcion_dispositivo_id uuid not null references public.device_receptions(id) on delete cascade,
  fk_accesorio_dispositivo_id uuid references public.device_accessories(id) on delete restrict,
  item_role text not null default 'ACCESSORY' check (item_role in ('ACCESSORY','PERIPHERAL','LOOSE_COMPONENT','OTHER')),
  quantity smallint not null default 1 check (quantity between 1 and 100),
  description text,
  observation text,
  created_at timestamptz not null default now(),
  check (fk_accesorio_dispositivo_id is not null or nullif(btrim(description),'') is not null),
  check (description is null or char_length(btrim(description)) between 2 and 200),
  check (observation is null or char_length(btrim(observation)) <= 500)
);
create index if not exists ix_reception_accessories_org_reception on public.reception_accessories(fk_organizacion_id,fk_recepcion_dispositivo_id);

create table if not exists public.reception_hardware_items (
  id uuid primary key default gen_random_uuid(),
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  fk_recepcion_dispositivo_id uuid not null references public.device_receptions(id) on delete cascade,
  component_kind text not null check (component_kind in ('CPU','MOTHERBOARD','RAM','GPU','STORAGE','PSU','COOLING','OTHER')),
  installation_state text not null default 'INSTALLED' check (installation_state in ('INSTALLED','DELIVERED_LOOSE')),
  evidence_basis text not null default 'OBSERVED' check (evidence_basis in ('OBSERVED','DECLARED')),
  fk_processor_model_id uuid references public.processor_models(id) on delete restrict,
  fk_motherboard_model_id uuid references public.motherboard_models(id) on delete restrict,
  fk_gpu_model_id uuid references public.gpu_models(id) on delete restrict,
  fk_ram_type_id uuid references public.ram_types(id) on delete restrict,
  fk_ram_speed_id uuid references public.ram_speeds(id) on delete restrict,
  fk_ram_form_factor_id uuid references public.ram_form_factors(id) on delete restrict,
  fk_storage_type_id uuid references public.storage_types(id) on delete restrict,
  fk_storage_interface_id uuid references public.storage_interfaces(id) on delete restrict,
  fk_storage_form_factor_id uuid references public.storage_form_factors(id) on delete restrict,
  manufacturer text,
  model text,
  serial_number text,
  capacity_mb integer check (capacity_mb is null or capacity_mb > 0),
  capacity_gb integer check (capacity_gb is null or capacity_gb > 0),
  quantity smallint not null default 1 check (quantity between 1 and 100),
  power_watts integer check (power_watts is null or power_watts > 0),
  notes text check (notes is null or char_length(notes) <= 1000),
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now()
);
create index if not exists ix_reception_hardware_items_org_reception on public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,sort_order);
create index if not exists ix_reception_hardware_items_processor on public.reception_hardware_items(fk_processor_model_id) where fk_processor_model_id is not null;
create index if not exists ix_reception_hardware_items_motherboard on public.reception_hardware_items(fk_motherboard_model_id) where fk_motherboard_model_id is not null;
create index if not exists ix_reception_hardware_items_gpu on public.reception_hardware_items(fk_gpu_model_id) where fk_gpu_model_id is not null;

alter table public.reception_accessories enable row level security;
alter table public.reception_hardware_items enable row level security;
drop policy if exists reception_accessories_read on public.reception_accessories;
create policy reception_accessories_read on public.reception_accessories for select to authenticated
  using (fk_organizacion_id=(select public.current_organization_id()));
drop policy if exists reception_hardware_items_read on public.reception_hardware_items;
create policy reception_hardware_items_read on public.reception_hardware_items for select to authenticated
  using (fk_organizacion_id=(select public.current_organization_id()));
grant select on public.reception_accessories, public.reception_hardware_items to authenticated;
revoke insert, update, delete on public.reception_accessories, public.reception_hardware_items from anon, authenticated;

-- La identidad OEM conserva marca/modelo; una PC armada o desconocida no los inventa.
create or replace function public.save_customer_device_identification(
  p_customer_id uuid, p_device_type_id uuid, p_device_brand_id uuid, p_device_model_id uuid,
  p_serial_number text default null, p_observations text default null, p_customer_device_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid; v_type_code text; v_kind text;
begin
  if not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  select code into v_type_code from public.device_types where id=p_device_type_id and is_active;
  if v_type_code is null then raise exception 'INVALID_DEVICE_TYPE'; end if;
  v_kind:=case when v_type_code='desktop_pc' then coalesce(nullif(p_observations,''),'UNKNOWN') else null end;
  if v_kind is not null and v_kind not in ('CUSTOM','OEM','UNKNOWN') then raise exception 'INVALID_DESKTOP_IDENTITY_KIND'; end if;
  if v_type_code<>'desktop_pc' or v_kind='OEM' then
    if not exists(select 1 from public.device_type_brands r join public.device_brands b on b.id=r.fk_marca_dispositivo_id where r.fk_tipo_dispositivo_id=p_device_type_id and r.fk_marca_dispositivo_id=p_device_brand_id and b.is_active and (b.alcance='GLOBAL' or b.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_BRAND'; end if;
    if not exists(select 1 from public.device_models m where m.id=p_device_model_id and m.fk_tipo_dispositivo_id=p_device_type_id and m.fk_marca_dispositivo_id=p_device_brand_id and m.is_active and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  else
    p_device_brand_id:=null; p_device_model_id:=null;
  end if;
  if char_length(coalesce(p_serial_number,''))>120 then raise exception 'INVALID_DEVICE_DATA'; end if;
  if p_customer_device_id is null then
    insert into public.customer_devices(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,numero_serie,desktop_identity_kind,created_by)
    values(v_org,p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,nullif(btrim(p_serial_number),''),v_kind,auth.uid()) returning id into v_id;
  else
    update public.customer_devices set fk_tipo_dispositivo_id=p_device_type_id,fk_marca_dispositivo_id=p_device_brand_id,fk_modelo_dispositivo_id=p_device_model_id,numero_serie=nullif(btrim(p_serial_number),''),desktop_identity_kind=v_kind,updated_at=now()
    where id=p_customer_device_id and fk_cliente_id=p_customer_id and fk_organizacion_id=v_org returning id into v_id;
    if v_id is null then raise exception 'INVALID_DEVICE'; end if;
  end if;
  return v_id;
end $$;
revoke all on function public.save_customer_device_identification(uuid,uuid,uuid,uuid,text,text,uuid) from public,anon;
grant execute on function public.save_customer_device_identification(uuid,uuid,uuid,uuid,text,text,uuid) to authenticated;

-- Extiende la confirmación canónica y congela el hardware observado de Desktop PC.
create or replace function public.confirmar_recepcion_dispositivo(
  p_dispositivo_cliente_id uuid, p_problema_informado text, p_observaciones text,
  p_resultados jsonb, p_intake_metadata jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_org uuid:=public.assert_reception_owner(); v_type_code text; v_item jsonb; v_sort integer:=0;
begin
  if jsonb_typeof(p_intake_metadata)<>'object' then raise exception 'INVALID_INTAKE_METADATA'; end if;
  if p_intake_metadata::text ~* '(password|contraseña|pattern_value|secret|credential_value)' then raise exception 'SENSITIVE_DATA_NOT_ALLOWED'; end if;
  v_id:=public.confirmar_recepcion_dispositivo(p_dispositivo_cliente_id,p_problema_informado,p_observaciones,p_resultados);
  select t.code into v_type_code from public.customer_devices d join public.device_types t on t.id=d.fk_tipo_dispositivo_id where d.id=p_dispositivo_cliente_id and d.fk_organizacion_id=v_org;
  update public.device_receptions set
    power_state=nullif(p_intake_metadata->>'powerState',''), image_state=nullif(p_intake_metadata->>'imageState',''), charge_state=nullif(p_intake_metadata->>'chargeState',''),
    access_available=nullif(p_intake_metadata->>'accessAvailable','')::boolean, access_method=nullif(p_intake_metadata->>'accessMethod',''), credential_provided=coalesce((p_intake_metadata->>'credentialProvided')::boolean,false),
    post_state=case when v_type_code='desktop_pc' then nullif(p_intake_metadata->>'postState','') else null end,
    os_boot_state=case when v_type_code='desktop_pc' then nullif(p_intake_metadata->>'osBootState','') else null end,
    internal_inventory_status=case when v_type_code='desktop_pc' then coalesce(nullif(p_intake_metadata->>'inventoryStatus',''),'NOT_PERFORMED') else null end,
    power_test_reason=case when v_type_code='desktop_pc' then nullif(btrim(p_intake_metadata->>'powerTestReason'),'') else null end
  where id=v_id and fk_organizacion_id=v_org;
  if v_type_code='desktop_pc' and coalesce(p_intake_metadata->>'inventoryStatus','NOT_PERFORMED')<>'NOT_PERFORMED' then
    insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,fk_processor_model_id,sort_order)
      select v_org,v_id,'CPU',h.fk_processor_model_id,10 from public.customer_device_hardware_profiles h where h.fk_customer_device_id=p_dispositivo_cliente_id and h.fk_processor_model_id is not null;
    insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,fk_motherboard_model_id,sort_order)
      select v_org,v_id,'MOTHERBOARD',d.fk_motherboard_model_id,20 from public.customer_devices d where d.id=p_dispositivo_cliente_id and d.fk_motherboard_model_id is not null;
    insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,fk_gpu_model_id,sort_order)
      select v_org,v_id,'GPU',h.gpu_model_id,30 from public.customer_device_hardware_profiles h where h.fk_customer_device_id=p_dispositivo_cliente_id and h.gpu_model_id is not null;
    insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,fk_ram_type_id,fk_ram_speed_id,fk_ram_form_factor_id,manufacturer,model,capacity_mb,sort_order)
      select v_org,v_id,'RAM',r.fk_ram_type_id,r.fk_ram_speed_id,r.fk_ram_form_factor_id,r.manufacturer,r.model,r.capacity_mb,100+row_number() over(order by r.created_at,r.id) from public.customer_device_ram_modules r where r.fk_customer_device_id=p_dispositivo_cliente_id;
    insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,fk_storage_type_id,fk_storage_interface_id,fk_storage_form_factor_id,manufacturer,model,serial_number,capacity_gb,notes,sort_order)
      select v_org,v_id,'STORAGE',s.fk_storage_type_id,s.fk_storage_interface_id,s.fk_storage_form_factor_id,s.manufacturer,s.model,s.serial_number,s.capacity_gb,s.condition,200+row_number() over(order by s.created_at,s.id) from public.customer_device_storage_drives s where s.fk_customer_device_id=p_dispositivo_cliente_id;
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_intake_metadata->'receptionItems','[]'::jsonb)) loop
    insert into public.reception_accessories(fk_organizacion_id,fk_recepcion_dispositivo_id,fk_accesorio_dispositivo_id,item_role,quantity,description,observation)
    values(v_org,v_id,nullif(v_item->>'accessoryId','')::uuid,coalesce(nullif(v_item->>'role',''),'ACCESSORY'),coalesce(nullif(v_item->>'quantity','')::smallint,1),nullif(btrim(v_item->>'description'),''),nullif(btrim(v_item->>'observation'),''));
  end loop;
  return v_id;
end $$;
revoke all on function public.confirmar_recepcion_dispositivo(uuid,text,text,jsonb,jsonb) from public,anon;
grant execute on function public.confirmar_recepcion_dispositivo(uuid,text,text,jsonb,jsonb) to authenticated;

-- Configuración data-driven de Desktop PC.
insert into public.device_field_options(fk_campo_dispositivo_id,value,label,sort_order,is_active)
select f.id,v.value,v.label,v.sort_order,true from public.device_fields f cross join (values
 ('CUSTOM','Armada / Custom',10),('OEM','OEM / Prearmada',20),('UNKNOWN','Desconocida',30)
) v(value,label,sort_order) where f.key='equipment_kind'
on conflict (fk_campo_dispositivo_id,value) do update set label=excluded.label,sort_order=excluded.sort_order,is_active=true;
update public.device_type_fields b set is_active=true,required=true
from public.device_fields f, public.device_types t
where b.fk_campo_dispositivo_id=f.id and b.fk_tipo_dispositivo_id=t.id and t.code='desktop_pc' and f.key='equipment_kind';

insert into public.device_reception_controls(key,label,descripcion,is_active,is_critical)
values
 ('desktop_case','Gabinete','Estado exterior del gabinete',true,false),
 ('desktop_side_panel','Panel lateral','Presencia, daño y tornillos',true,false),
 ('desktop_front','Frente del gabinete','Estado del frente',true,false),
 ('desktop_front_ports','Puertos frontales','Inspección visual o prueba rápida',true,false),
 ('desktop_power_button','Botón de encendido','Estado físico y funcionamiento observable',true,false),
 ('desktop_reset_button','Botón Reset','Estado cuando corresponda',true,false),
 ('desktop_internal_cleanliness','Limpieza interior','Cantidad de polvo observada',true,false),
 ('desktop_liquid_indicators','Humedad o líquido','Indicios visibles sin energizar',true,true),
 ('desktop_internal_wiring','Cableado interno','Orden y conexiones visibles',true,false),
 ('desktop_motherboard_visual','Motherboard','Daños visibles',true,true),
 ('desktop_psu_visual','Fuente','Suciedad, olor o daño visible',true,true),
 ('desktop_gpu_visual','GPU dedicada','Estado visual cuando exista',true,false),
 ('desktop_fans','Ventiladores','Giro o ruido en prueba rápida',true,false),
 ('desktop_abnormal_noise','Ruido anormal','Ruido percibido en prueba rápida',true,false),
 ('desktop_detected_drives','Unidades detectadas','Detección rápida, no diagnóstico',true,false),
 ('desktop_detected_ram','RAM detectada','Detección rápida, no MemTest',true,false)
on conflict (key) do update set label=excluded.label,descripcion=excluded.descripcion,is_active=true,is_critical=excluded.is_critical;
insert into public.device_type_reception_controls(fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id,sort_order,obligatorio,is_active)
select t.id,c.id,row_number() over(order by c.key)*10,false,true from public.device_types t cross join public.device_reception_controls c
where t.code='desktop_pc' and c.key like 'desktop_%'
on conflict (fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id) do update set obligatorio=false,is_active=true;

insert into public.device_form_sections(key,title,description,alcance,is_active,sort_order,ui_config)
values
 ('pc_memory','Memoria RAM','Módulos observados dentro del gabinete.','GLOBAL',true,30,'{"container":"repeatable-section","columns":{"base":1,"md":2}}'),
 ('pc_storage','Almacenamiento','Unidades instaladas observadas.','GLOBAL',true,50,'{"container":"repeatable-section","columns":{"base":1,"md":2}}'),
 ('pc_power_supply','Fuente de alimentación','Datos visibles de la fuente instalada.','GLOBAL',true,60,'{"columns":{"base":1,"md":2}}'),
 ('pc_cooling','Refrigeración','Configuración visible, sin desmontajes innecesarios.','GLOBAL',true,70,'{"columns":{"base":1,"md":2}}')
on conflict (key) do update set title=excluded.title,description=excluded.description,is_active=true,sort_order=excluded.sort_order,ui_config=excluded.ui_config;

insert into public.device_fields(key,label,field_type,data_source_key,placeholder,help_text,validation,alcance,is_active)
values
 ('psu_manufacturer','Marca de la fuente','TEXT',null,'Ej. Corsair o genérica','Opcional si no hay etiqueta visible.','{"max_length":120}','GLOBAL',true),
 ('psu_model','Modelo de la fuente','TEXT',null,'Ej. CV550',null,'{"max_length":120}','GLOBAL',true),
 ('psu_watts','Potencia nominal (W)','NUMBER',null,'Ej. 550','Potencia declarada en la etiqueta; no implica potencia comprobada.','{"min_value":1,"max_value":5000}','GLOBAL',true),
 ('cpu_cooler_kind','Cooler de CPU','SELECT',null,'Seleccionar tipo',null,'{}','GLOBAL',true),
 ('case_fan_count','Ventiladores visibles','NUMBER',null,'Cantidad','No requiere inventariar cada ventilador.','{"min_value":0,"max_value":50}','GLOBAL',true),
 ('cooling_observation','Observación de refrigeración','TEXTAREA',null,'Ej. 3 frontales y 1 trasero',null,'{"max_length":500}','GLOBAL',true)
on conflict (key) do update set label=excluded.label,field_type=excluded.field_type,placeholder=excluded.placeholder,help_text=excluded.help_text,validation=excluded.validation,is_active=true;

update public.device_fields set data_source_key='hardware_gpu_brand' where key='gpu_brand_id';
update public.device_fields set data_source_key='hardware_gpu_family' where key='gpu_family_id';
update public.device_fields set data_source_key='hardware_gpu_model' where key='gpu_model_id';

insert into public.device_field_options(fk_campo_dispositivo_id,value,label,sort_order,is_active)
select f.id,v.value,v.label,v.sort_order,true from public.device_fields f cross join (values
 ('NONE','Sin GPU dedicada',10),('DEDICATED','GPU dedicada observada',20),('UNDETERMINED','No determinado',30)
) v(value,label,sort_order) where f.key='gpu_mode'
on conflict (fk_campo_dispositivo_id,value) do update set label=excluded.label,sort_order=excluded.sort_order,is_active=true;
insert into public.device_field_options(fk_campo_dispositivo_id,value,label,sort_order,is_active)
select f.id,v.value,v.label,v.sort_order,true from public.device_fields f cross join (values
 ('STOCK','Stock / original',10),('AIR_TOWER','Torre / Air cooler',20),('AIO','AIO líquida',30),('OTHER','Otro',40),('UNIDENTIFIED','No identificado',50)
) v(value,label,sort_order) where f.key='cpu_cooler_kind'
on conflict (fk_campo_dispositivo_id,value) do update set label=excluded.label,sort_order=excluded.sort_order,is_active=true;

insert into public.device_type_fields(fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,sort_order,required,overrides,is_active)
select t.id,s.id,f.id,x.sort_order,false,x.overrides::jsonb,true
from public.device_types t
join (values
 ('pc_hardware','gpu_mode',25,'{"component":"radio-group"}'),
 ('pc_hardware','gpu_family_id',35,'{"dependsOn":"gpu_brand_id","catalog":"gpu_families"}'),
 ('pc_memory','ram_modules',10,'{"component":"ram-modules"}'),
 ('pc_storage','storage_drives',10,'{"component":"storage-drives"}'),
 ('pc_power_supply','psu_manufacturer',10,'{}'),('pc_power_supply','psu_model',20,'{}'),('pc_power_supply','psu_watts',30,'{}'),
 ('pc_cooling','cpu_cooler_kind',10,'{}'),('pc_cooling','case_fan_count',20,'{}'),('pc_cooling','cooling_observation',30,'{"fullWidth":true}')
) x(section_key,field_key,sort_order,overrides) on true
join public.device_form_sections s on s.key=x.section_key
join public.device_fields f on f.key=x.field_key
where t.code='desktop_pc'
on conflict (fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id)
do update set sort_order=excluded.sort_order,required=false,overrides=excluded.overrides,is_active=true;

-- GPU dependiente: no se muestra catálogo si no se declaró dedicada.
insert into public.device_field_dependencies(fk_tipo_dispositivo_campo_id,fk_tipo_dispositivo_campo_padre_id,operator,expected_value)
select child.id,parent.id,'EQUALS','"DEDICATED"'::jsonb
from public.device_type_fields child
join public.device_fields cf on cf.id=child.fk_campo_dispositivo_id and cf.key in ('gpu_brand_id','gpu_family_id','gpu_model_id')
join public.device_type_fields parent on parent.fk_tipo_dispositivo_id=child.fk_tipo_dispositivo_id
join public.device_fields pf on pf.id=parent.fk_campo_dispositivo_id and pf.key='gpu_mode'
join public.device_types t on t.id=child.fk_tipo_dispositivo_id and t.code='desktop_pc'
where not exists(select 1 from public.device_field_dependencies d where d.fk_tipo_dispositivo_campo_id=child.id and d.fk_tipo_dispositivo_campo_padre_id=parent.id);

-- Completa el snapshot con fuente y refrigeración observadas, almacenadas como campos relacionales del dispositivo.
-- Estos INSERT se ejecutan desde la función de confirmación mediante un trigger posterior.
create or replace function public.snapshot_desktop_auxiliary_hardware() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_type text; v_value record; v_psu_manufacturer text; v_psu_model text; v_psu_watts integer; v_cooler text; v_fans integer; v_note text;
begin
  select t.code into v_type from public.customer_devices d join public.device_types t on t.id=d.fk_tipo_dispositivo_id where d.id=new.fk_dispositivo_cliente_id;
  if v_type<>'desktop_pc' or coalesce(new.internal_inventory_status,'NOT_PERFORMED')='NOT_PERFORMED' then return new; end if;
  for v_value in select f.key,v.valor_texto from public.customer_device_field_values v join public.device_type_fields b on b.id=v.fk_tipo_dispositivo_campo_id join public.device_fields f on f.id=b.fk_campo_dispositivo_id where v.fk_dispositivo_cliente_id=new.fk_dispositivo_cliente_id loop
    case v_value.key when 'psu_manufacturer' then v_psu_manufacturer:=v_value.valor_texto when 'psu_model' then v_psu_model:=v_value.valor_texto when 'psu_watts' then v_psu_watts:=nullif(v_value.valor_texto,'')::integer when 'cpu_cooler_kind' then v_cooler:=v_value.valor_texto when 'case_fan_count' then v_fans:=nullif(v_value.valor_texto,'')::integer when 'cooling_observation' then v_note:=v_value.valor_texto else null; end case;
  end loop;
  if num_nonnulls(v_psu_manufacturer,v_psu_model,v_psu_watts)>0 then insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,manufacturer,model,power_watts,sort_order) values(new.fk_organizacion_id,new.id,'PSU',v_psu_manufacturer,v_psu_model,v_psu_watts,300); end if;
  if num_nonnulls(v_cooler,v_fans,v_note)>0 then insert into public.reception_hardware_items(fk_organizacion_id,fk_recepcion_dispositivo_id,component_kind,model,quantity,notes,sort_order) values(new.fk_organizacion_id,new.id,'COOLING',v_cooler,coalesce(v_fans,1),v_note,400); end if;
  return new;
end $$;
drop trigger if exists trg_snapshot_desktop_auxiliary_hardware on public.device_receptions;
create trigger trg_snapshot_desktop_auxiliary_hardware after update of internal_inventory_status on public.device_receptions for each row execute function public.snapshot_desktop_auxiliary_hardware();
revoke all on function public.snapshot_desktop_auxiliary_hardware() from public,anon,authenticated;
