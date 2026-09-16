begin;

-- Orden estable para que PostgreSQL sea la fuente de verdad de la presentación.
alter table public.secciones_formulario_dispositivo
  add column orden integer not null default 0;

-- Los colores creados por una organización no se convierten en datos globales.
alter table public.colores_dispositivo
  drop constraint uq_colores_dispositivo_nombre_normalizado;
alter table public.colores_dispositivo
  add column alcance text not null default 'GLOBAL',
  add column fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  add constraint ck_colores_dispositivo_alcance
    check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  add constraint uq_colores_dispositivo_nombre_alcance
    unique nulls not distinct (nombre_normalizado, fk_organizacion_id);

drop policy colores_dispositivo_lectura on public.colores_dispositivo;
create policy colores_dispositivo_lectura on public.colores_dispositivo
  for select to authenticated
  using (activo and (alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()));

create table public.categorias_componente (
  id uuid primary key default gen_random_uuid(),
  clave text not null,
  nombre text not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_categorias_componente_clave check (clave ~ '^[A-Z][A-Z_]{1,40}$'),
  constraint uq_categorias_componente_clave unique (clave)
);

create table public.marcas_componente (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_marcas_componente_nombre check (char_length(btrim(nombre)) between 2 and 120),
  constraint ck_marcas_componente_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_marcas_componente_nombre_alcance unique nulls not distinct (nombre_normalizado, fk_organizacion_id)
);

create table public.categorias_componente_marcas (
  fk_categoria_componente_id uuid not null references public.categorias_componente(id) on delete restrict,
  fk_marca_componente_id uuid not null references public.marcas_componente(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (fk_categoria_componente_id, fk_marca_componente_id)
);

create table public.modelos_componente (
  id uuid primary key default gen_random_uuid(),
  fk_categoria_componente_id uuid not null,
  fk_marca_componente_id uuid not null,
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fk_modelos_componente_categoria_marca foreign key (fk_categoria_componente_id, fk_marca_componente_id)
    references public.categorias_componente_marcas(fk_categoria_componente_id, fk_marca_componente_id) on delete restrict,
  constraint ck_modelos_componente_nombre check (char_length(btrim(nombre)) between 2 and 200),
  constraint ck_modelos_componente_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_modelos_componente_nombre_alcance unique nulls not distinct (fk_categoria_componente_id, fk_marca_componente_id, nombre_normalizado, fk_organizacion_id),
  constraint uq_modelos_componente_integridad unique (id, fk_categoria_componente_id, fk_marca_componente_id)
);

create index ix_categorias_componente_marcas_marca on public.categorias_componente_marcas(fk_marca_componente_id, fk_categoria_componente_id);
create index ix_modelos_componente_catalogo on public.modelos_componente(fk_categoria_componente_id, fk_marca_componente_id, nombre_normalizado);

create table public.memoria_ram_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_dispositivo_cliente_id uuid not null references public.dispositivos_clientes(id) on delete restrict,
  capacidad_gb integer not null,
  cantidad smallint not null,
  soldada boolean not null default false,
  created_at timestamptz not null default now(),
  constraint ck_memoria_ram_dispositivo_capacidad check (capacidad_gb between 1 and 8192),
  constraint ck_memoria_ram_dispositivo_cantidad check (cantidad between 1 and 128)
);
create index ix_memoria_ram_dispositivo_dispositivo on public.memoria_ram_dispositivo(fk_dispositivo_cliente_id);

create table public.tipos_almacenamiento (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_tipos_almacenamiento_nombre check (char_length(btrim(nombre)) between 2 and 80),
  constraint ck_tipos_almacenamiento_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_tipos_almacenamiento_nombre_alcance unique nulls not distinct (nombre_normalizado, fk_organizacion_id)
);

create table public.almacenamientos_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_dispositivo_cliente_id uuid not null references public.dispositivos_clientes(id) on delete restrict,
  fk_tipo_almacenamiento_id uuid not null references public.tipos_almacenamiento(id) on delete restrict,
  capacidad_gb integer not null,
  cantidad smallint not null,
  created_at timestamptz not null default now(),
  constraint ck_almacenamientos_dispositivo_capacidad check (capacidad_gb between 1 and 1048576),
  constraint ck_almacenamientos_dispositivo_cantidad check (cantidad between 1 and 128)
);
create index ix_almacenamientos_dispositivo_dispositivo on public.almacenamientos_dispositivo(fk_dispositivo_cliente_id);

create table public.accesorios_dispositivo (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_accesorios_dispositivo_nombre check (char_length(btrim(nombre)) between 2 and 120),
  constraint ck_accesorios_dispositivo_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_accesorios_dispositivo_nombre_alcance unique nulls not distinct (nombre_normalizado, fk_organizacion_id)
);

create table public.dispositivos_clientes_accesorios (
  fk_dispositivo_cliente_id uuid not null references public.dispositivos_clientes(id) on delete restrict,
  fk_accesorio_dispositivo_id uuid not null references public.accesorios_dispositivo(id) on delete restrict,
  cantidad smallint not null default 1,
  created_at timestamptz not null default now(),
  primary key (fk_dispositivo_cliente_id, fk_accesorio_dispositivo_id),
  constraint ck_dispositivos_clientes_accesorios_cantidad check (cantidad between 1 and 100)
);

create table public.dependencias_campo_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_tipo_dispositivo_campo_id uuid not null references public.tipos_dispositivo_campos(id) on delete restrict,
  fk_tipo_dispositivo_campo_padre_id uuid not null references public.tipos_dispositivo_campos(id) on delete restrict,
  operador text not null,
  valor_esperado jsonb,
  created_at timestamptz not null default now(),
  constraint ck_dependencias_campo_dispositivo_operador check (operador in ('EQUALS','NOT_EQUALS','IN','NOT_EMPTY','EMPTY')),
  constraint ck_dependencias_campo_dispositivo_distintas check (fk_tipo_dispositivo_campo_id <> fk_tipo_dispositivo_campo_padre_id),
  constraint uq_dependencias_campo_dispositivo unique (fk_tipo_dispositivo_campo_id, fk_tipo_dispositivo_campo_padre_id, operador)
);

-- Las categorías son estructura, no marcas ni modelos de negocio precargados.
insert into public.categorias_componente(clave, nombre) values
  ('GABINETE','Gabinete'), ('FUENTE_ALIMENTACION','Fuente de alimentación'),
  ('PLACA_MADRE','Placa madre'), ('TARJETA_GRAFICA','Tarjeta gráfica'),
  ('COOLER_PROCESADOR','Refrigeración del procesador'), ('ADAPTADOR_WIFI','Adaptador Wi-Fi');

-- Secciones y campos de PC. No se insertan marcas, modelos, colores,
-- tipos de almacenamiento ni accesorios.
insert into public.secciones_formulario_dispositivo(clave,titulo,descripcion,alcance,orden) values
  ('gabinete_fuente','Gabinete y fuente','Gabinete, ventilación y fuente de alimentación.', 'GLOBAL',10),
  ('placa_madre','Placa madre','Catálogo reutilizable organizado por marca y modelo.', 'GLOBAL',30),
  ('graficos','Tarjeta gráfica','Gráficos integrados o tarjeta dedicada.', 'GLOBAL',40),
  ('refrigeracion_procesador','Refrigeración del procesador','Cooler original o independiente.', 'GLOBAL',50),
  ('sistema_operativo','Sistema operativo','Sistema instalado y versión o distribución.', 'GLOBAL',60),
  ('conectividad_wifi','Conectividad Wi-Fi','Capacidad Wi-Fi integrada o mediante adaptador externo.', 'GLOBAL',70),
  ('unidad_optica','Unidad óptica',null,'GLOBAL',80)
on conflict (clave,fk_organizacion_id) do update set titulo=excluded.titulo,descripcion=excluded.descripcion,orden=excluded.orden,activo=true;
update public.secciones_formulario_dispositivo set orden=20 where clave='procesador' and alcance='GLOBAL';

insert into public.campos_dispositivo(clave,etiqueta,tipo_campo,clave_fuente_datos,placeholder,texto_ayuda,validacion,alcance) values
  ('case_brand_id','Marca del gabinete','SELECT','hardware_case_brand','Seleccionar marca','Opcional cuando se desconozca.','{}','GLOBAL'),
  ('case_model_id','Modelo del gabinete','SELECT','hardware_case_model','Seleccionar modelo',null,'{}','GLOBAL'),
  ('case_fan_count','Cantidad de coolers/ventiladores','NUMBER',null,'0',null,'{"min_value":0,"max_value":50}','GLOBAL'),
  ('case_has_original_power_supply','¿El gabinete incluye la fuente de alimentación original?','RADIO',null,null,null,'{}','GLOBAL'),
  ('included_power_supply_name','Nombre/modelo completo de la fuente incluida','TEXT',null,'Ej. BRB 500W',null,'{"max_length":200}','GLOBAL'),
  ('external_power_supply_brand_id','Marca de la fuente externa','SELECT','hardware_power_supply_brand','Seleccionar marca',null,'{}','GLOBAL'),
  ('external_power_supply_model_id','Fuente de alimentación','SELECT','hardware_power_supply_model','Seleccionar modelo',null,'{}','GLOBAL'),
  ('motherboard_brand_id','Marca de la placa madre','SELECT','hardware_motherboard_brand','Seleccionar marca',null,'{}','GLOBAL'),
  ('motherboard_model_id','Placa madre / Motherboard','SELECT','hardware_motherboard_model','Seleccionar modelo',null,'{}','GLOBAL'),
  ('graphics_mode','Tipo de gráficos','RADIO',null,null,null,'{}','GLOBAL'),
  ('gpu_brand_id','Marca de la tarjeta gráfica','SELECT','hardware_gpu_brand','Seleccionar marca',null,'{}','GLOBAL'),
  ('gpu_model_id','Tarjeta gráfica dedicada','SELECT','hardware_gpu_model','Seleccionar modelo',null,'{}','GLOBAL'),
  ('cpu_cooler_mode','Tipo de refrigeración','RADIO',null,null,null,'{}','GLOBAL'),
  ('cpu_cooler_brand_id','Marca del cooler independiente','SELECT','hardware_cpu_cooler_brand','Seleccionar marca',null,'{}','GLOBAL'),
  ('cpu_cooler_model_id','Cooler independiente','SELECT','hardware_cpu_cooler_model','Seleccionar modelo',null,'{}','GLOBAL'),
  ('operating_system_kind','Sistema operativo','SELECT',null,'Seleccionar sistema',null,'{}','GLOBAL'),
  ('operating_system_version','Versión / distribución','TEXT',null,'Ej. Windows 11 Pro o Ubuntu 24.04',null,'{"max_length":120}','GLOBAL'),
  ('has_wifi','¿Posee Wi-Fi?','RADIO',null,null,null,'{}','GLOBAL'),
  ('wifi_mode','Tipo de Wi-Fi','RADIO',null,null,null,'{}','GLOBAL'),
  ('wifi_brand_id','Marca del adaptador/tarjeta Wi-Fi','SELECT','hardware_wifi_brand','Seleccionar marca',null,'{}','GLOBAL'),
  ('wifi_model_id','Adaptador/tarjeta Wi-Fi','SELECT','hardware_wifi_model','Seleccionar modelo',null,'{}','GLOBAL'),
  ('has_optical_drive','¿Posee lector/grabadora de CD/DVD?','RADIO',null,null,null,'{}','GLOBAL')
on conflict (clave,fk_organizacion_id) do update set etiqueta=excluded.etiqueta,tipo_campo=excluded.tipo_campo,clave_fuente_datos=excluded.clave_fuente_datos,placeholder=excluded.placeholder,texto_ayuda=excluded.texto_ayuda,validacion=excluded.validacion,activo=true;

insert into public.opciones_campo_dispositivo(fk_campo_dispositivo_id,valor,etiqueta,orden)
select c.id,o.valor,o.etiqueta,o.orden from public.campos_dispositivo c join (values
  ('case_has_original_power_supply','true','Sí',10),('case_has_original_power_supply','false','No',20),
  ('graphics_mode','INTEGRATED','Gráficos integrados',10),('graphics_mode','DEDICATED','Tarjeta gráfica dedicada',20),
  ('cpu_cooler_mode','ORIGINAL','Cooler incluido/original del procesador',10),('cpu_cooler_mode','EXTERNAL','Cooler independiente',20),
  ('operating_system_kind','WINDOWS','Windows',10),('operating_system_kind','LINUX','Linux',20),('operating_system_kind','MACOS','macOS',30),('operating_system_kind','OTHER','Otro',40),('operating_system_kind','NONE','Sin sistema operativo',50),
  ('has_wifi','true','Sí',10),('has_wifi','false','No',20),
  ('wifi_mode','INTEGRATED','Wi-Fi integrado',10),('wifi_mode','EXTERNAL','Adaptador/tarjeta externa',20),
  ('has_optical_drive','true','Sí',10),('has_optical_drive','false','No',20)
) o(clave,valor,etiqueta,orden) on c.clave=o.clave and c.alcance='GLOBAL'
on conflict (fk_campo_dispositivo_id,valor) do update set etiqueta=excluded.etiqueta,orden=excluded.orden,activo=true;

with asignaciones(seccion,clave,orden,obligatorio) as (values
  ('gabinete_fuente','case_brand_id',10,false),('gabinete_fuente','case_model_id',20,false),('gabinete_fuente','case_fan_count',30,true),
  ('gabinete_fuente','case_has_original_power_supply',40,true),('gabinete_fuente','included_power_supply_name',50,false),
  ('gabinete_fuente','external_power_supply_brand_id',60,false),('gabinete_fuente','external_power_supply_model_id',70,false),
  ('placa_madre','motherboard_brand_id',10,false),('placa_madre','motherboard_model_id',20,false),
  ('graficos','graphics_mode',10,true),('graficos','gpu_brand_id',20,false),('graficos','gpu_model_id',30,false),
  ('refrigeracion_procesador','cpu_cooler_mode',10,true),('refrigeracion_procesador','cpu_cooler_brand_id',20,false),('refrigeracion_procesador','cpu_cooler_model_id',30,false),
  ('sistema_operativo','operating_system_kind',10,true),('sistema_operativo','operating_system_version',20,false),
  ('conectividad_wifi','has_wifi',10,true),('conectividad_wifi','wifi_mode',20,false),('conectividad_wifi','wifi_brand_id',30,false),('conectividad_wifi','wifi_model_id',40,false),
  ('unidad_optica','has_optical_drive',10,true)
)
insert into public.tipos_dispositivo_campos(fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,orden,obligatorio)
select t.id,s.id,c.id,a.orden,a.obligatorio from asignaciones a
join public.tipos_dispositivo t on t.nombre_normalizado='pc'
join public.secciones_formulario_dispositivo s on s.clave=a.seccion and s.alcance='GLOBAL'
join public.campos_dispositivo c on c.clave=a.clave and c.alcance='GLOBAL'
on conflict (fk_tipo_dispositivo_id,fk_campo_dispositivo_id) do update set fk_seccion_formulario_dispositivo_id=excluded.fk_seccion_formulario_dispositivo_id,orden=excluded.orden,obligatorio=excluded.obligatorio,activo=true;

with reglas(hijo,padre,operador,esperado) as (values
  ('case_model_id','case_brand_id','NOT_EMPTY',null::jsonb),
  ('included_power_supply_name','case_has_original_power_supply','EQUALS','"true"'::jsonb),
  ('external_power_supply_brand_id','case_has_original_power_supply','EQUALS','"false"'::jsonb),
  ('external_power_supply_model_id','case_has_original_power_supply','EQUALS','"false"'::jsonb),
  ('motherboard_model_id','motherboard_brand_id','NOT_EMPTY',null::jsonb),
  ('gpu_brand_id','graphics_mode','EQUALS','"DEDICATED"'::jsonb),('gpu_model_id','graphics_mode','EQUALS','"DEDICATED"'::jsonb),
  ('gpu_model_id','gpu_brand_id','NOT_EMPTY',null::jsonb),
  ('cpu_cooler_brand_id','cpu_cooler_mode','EQUALS','"EXTERNAL"'::jsonb),('cpu_cooler_model_id','cpu_cooler_mode','EQUALS','"EXTERNAL"'::jsonb),
  ('cpu_cooler_model_id','cpu_cooler_brand_id','NOT_EMPTY',null::jsonb),
  ('operating_system_version','operating_system_kind','NOT_EQUALS','"NONE"'::jsonb),
  ('wifi_mode','has_wifi','EQUALS','"true"'::jsonb),
  ('wifi_brand_id','wifi_mode','EQUALS','"EXTERNAL"'::jsonb),('wifi_model_id','wifi_mode','EQUALS','"EXTERNAL"'::jsonb),
  ('wifi_model_id','wifi_brand_id','NOT_EMPTY',null::jsonb)
)
insert into public.dependencias_campo_dispositivo(fk_tipo_dispositivo_campo_id,fk_tipo_dispositivo_campo_padre_id,operador,valor_esperado)
select hijo.id,padre.id,r.operador,r.esperado from reglas r
join public.tipos_dispositivo t on t.nombre_normalizado='pc'
join public.tipos_dispositivo_campos hijo on hijo.fk_tipo_dispositivo_id=t.id
join public.campos_dispositivo ch on ch.id=hijo.fk_campo_dispositivo_id and ch.clave=r.hijo
join public.tipos_dispositivo_campos padre on padre.fk_tipo_dispositivo_id=t.id
join public.campos_dispositivo cp on cp.id=padre.fk_campo_dispositivo_id and cp.clave=r.padre
on conflict do nothing;

-- RLS: catálogos globales visibles y privados limitados a la organización.
alter table public.categorias_componente enable row level security;
alter table public.marcas_componente enable row level security;
alter table public.categorias_componente_marcas enable row level security;
alter table public.modelos_componente enable row level security;
alter table public.memoria_ram_dispositivo enable row level security;
alter table public.tipos_almacenamiento enable row level security;
alter table public.almacenamientos_dispositivo enable row level security;
alter table public.accesorios_dispositivo enable row level security;
alter table public.dispositivos_clientes_accesorios enable row level security;
alter table public.dependencias_campo_dispositivo enable row level security;

create policy categorias_componente_lectura on public.categorias_componente for select to authenticated using (activo);
create policy marcas_componente_lectura on public.marcas_componente for select to authenticated using (activo and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id()));
create policy categorias_componente_marcas_lectura on public.categorias_componente_marcas for select to authenticated using (exists(select 1 from public.marcas_componente m where m.id=fk_marca_componente_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())));
create policy modelos_componente_lectura on public.modelos_componente for select to authenticated using (activo and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id()));
create policy memoria_ram_dispositivo_lectura on public.memoria_ram_dispositivo for select to authenticated using (exists(select 1 from public.dispositivos_clientes d where d.id=fk_dispositivo_cliente_id and d.fk_organizacion_id=public.current_organization_id()));
create policy tipos_almacenamiento_lectura on public.tipos_almacenamiento for select to authenticated using (activo and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id()));
create policy almacenamientos_dispositivo_lectura on public.almacenamientos_dispositivo for select to authenticated using (exists(select 1 from public.dispositivos_clientes d where d.id=fk_dispositivo_cliente_id and d.fk_organizacion_id=public.current_organization_id()));
create policy accesorios_dispositivo_lectura on public.accesorios_dispositivo for select to authenticated using (activo and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id()));
create policy dispositivos_clientes_accesorios_lectura on public.dispositivos_clientes_accesorios for select to authenticated using (exists(select 1 from public.dispositivos_clientes d where d.id=fk_dispositivo_cliente_id and d.fk_organizacion_id=public.current_organization_id()));
create policy dependencias_campo_dispositivo_lectura on public.dependencias_campo_dispositivo for select to authenticated using (exists(select 1 from public.tipos_dispositivo_campos tc where tc.id=fk_tipo_dispositivo_campo_id and tc.activo));

revoke insert,update,delete on table public.categorias_componente,public.marcas_componente,public.categorias_componente_marcas,public.modelos_componente,public.memoria_ram_dispositivo,public.tipos_almacenamiento,public.almacenamientos_dispositivo,public.accesorios_dispositivo,public.dispositivos_clientes_accesorios,public.dependencias_campo_dispositivo from anon,authenticated;
grant select on table public.categorias_componente,public.marcas_componente,public.categorias_componente_marcas,public.modelos_componente,public.memoria_ram_dispositivo,public.tipos_almacenamiento,public.almacenamientos_dispositivo,public.accesorios_dispositivo,public.dispositivos_clientes_accesorios,public.dependencias_campo_dispositivo to authenticated;

create or replace function public.crear_color_dispositivo(p_nombre text)
returns public.colores_dispositivo language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_color public.colores_dispositivo;
begin
  if char_length(v_nombre) not between 2 and 80 then raise exception 'INVALID_DEVICE_COLOR'; end if;
  select * into v_color from public.colores_dispositivo where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_color; end if;
  insert into public.colores_dispositivo(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid())
  on conflict on constraint uq_colores_dispositivo_nombre_alcance do update set updated_at=now() returning * into v_color;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'COLOR_DISPOSITIVO_CREADO','COLOR_DISPOSITIVO',v_color.id,'{}');
  return v_color;
end $$;

create function public.crear_marca_componente(p_categoria text,p_nombre text)
returns public.marcas_componente language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_categoria uuid; v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_marca public.marcas_componente;
begin
  select id into v_categoria from public.categorias_componente where clave=upper(btrim(p_categoria)) and activo;
  if v_categoria is null or char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_COMPONENT_BRAND'; end if;
  select * into v_marca from public.marcas_componente where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if not found then
    insert into public.marcas_componente(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid())
    on conflict on constraint uq_marcas_componente_nombre_alcance do update set updated_at=now() returning * into v_marca;
  end if;
  insert into public.categorias_componente_marcas values(v_categoria,v_marca.id,now()) on conflict do nothing;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MARCA_COMPONENTE_VINCULADA','MARCA_COMPONENTE',v_marca.id,jsonb_build_object('categoria',upper(btrim(p_categoria))));
  return v_marca;
end $$;

create function public.crear_modelo_componente(p_categoria text,p_marca_componente_id uuid,p_nombre text)
returns public.modelos_componente language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_categoria uuid; v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_modelo public.modelos_componente;
begin
  select c.id into v_categoria from public.categorias_componente c join public.categorias_componente_marcas cm on cm.fk_categoria_componente_id=c.id join public.marcas_componente m on m.id=cm.fk_marca_componente_id where c.clave=upper(btrim(p_categoria)) and c.activo and m.id=p_marca_componente_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org);
  if v_categoria is null or char_length(v_nombre) not between 2 and 200 then raise exception 'INVALID_COMPONENT_MODEL'; end if;
  select * into v_modelo from public.modelos_componente where fk_categoria_componente_id=v_categoria and fk_marca_componente_id=p_marca_componente_id and nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_modelo; end if;
  insert into public.modelos_componente(fk_categoria_componente_id,fk_marca_componente_id,nombre,alcance,fk_organizacion_id,created_by) values(v_categoria,p_marca_componente_id,v_nombre,'ORGANIZACION',v_org,auth.uid())
  on conflict on constraint uq_modelos_componente_nombre_alcance do update set updated_at=now() returning * into v_modelo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MODELO_COMPONENTE_CREADO','MODELO_COMPONENTE',v_modelo.id,jsonb_build_object('categoria',upper(btrim(p_categoria)),'marca_componente_id',p_marca_componente_id));
  return v_modelo;
end $$;

create function public.crear_tipo_almacenamiento(p_nombre text)
returns public.tipos_almacenamiento language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_tipo public.tipos_almacenamiento;
begin
  if char_length(v_nombre) not between 2 and 80 then raise exception 'INVALID_STORAGE_TYPE'; end if;
  select * into v_tipo from public.tipos_almacenamiento where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_tipo; end if;
  insert into public.tipos_almacenamiento(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid()) on conflict on constraint uq_tipos_almacenamiento_nombre_alcance do update set updated_at=now() returning * into v_tipo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'TIPO_ALMACENAMIENTO_CREADO','TIPO_ALMACENAMIENTO',v_tipo.id,'{}');
  return v_tipo;
end $$;

create function public.crear_accesorio_dispositivo(p_nombre text)
returns public.accesorios_dispositivo language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_accesorio public.accesorios_dispositivo;
begin
  if char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_ACCESSORY'; end if;
  select * into v_accesorio from public.accesorios_dispositivo where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_accesorio; end if;
  insert into public.accesorios_dispositivo(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid()) on conflict on constraint uq_accesorios_dispositivo_nombre_alcance do update set updated_at=now() returning * into v_accesorio;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'ACCESORIO_DISPOSITIVO_CREADO','ACCESORIO_DISPOSITIVO',v_accesorio.id,'{}');
  return v_accesorio;
end $$;

-- La RPC admite exclusivamente campos configurados para el tipo y valida los
-- catálogos y relaciones nuevamente dentro de la misma transacción.
drop function public.crear_dispositivo_cliente(uuid,uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,uuid);
create function public.crear_dispositivo_cliente(
  p_cliente_id uuid,p_tipo_dispositivo_id uuid,p_marca_dispositivo_id uuid,p_modelo_dispositivo_id uuid default null,
  p_variante_modelo_dispositivo_id uuid default null,p_color_dispositivo_id uuid default null,p_numero_serie text default null,
  p_marca_procesador_id uuid default null,p_familia_procesador_id uuid default null,p_modelo_procesador_id uuid default null,
  p_atributos jsonb default '{}'::jsonb,p_memorias jsonb default '[]'::jsonb,p_almacenamientos jsonb default '[]'::jsonb,p_accesorios jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid; v_es_pc boolean; v_par record; v_campo record; v_item jsonb; v_opcion uuid; v_categoria text; v_marca uuid; v_modelo uuid;
begin
  if jsonb_typeof(p_atributos)<>'object' or jsonb_typeof(p_memorias)<>'array' or jsonb_typeof(p_almacenamientos)<>'array' or jsonb_typeof(p_accesorios)<>'array' then raise exception 'INVALID_DEVICE_DATA'; end if;
  if not exists(select 1 from public.customers where id=p_cliente_id and organization_id=v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  select nombre_normalizado='pc' into v_es_pc from public.tipos_dispositivo where id=p_tipo_dispositivo_id and activo;
  if v_es_pc is null then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if not exists(select 1 from public.tipos_dispositivo_marcas tm join public.marcas_dispositivo m on m.id=tm.fk_marca_dispositivo_id where tm.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and tm.fk_marca_dispositivo_id=p_marca_dispositivo_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if p_modelo_dispositivo_id is not null and not exists(select 1 from public.modelos_dispositivo m where m.id=p_modelo_dispositivo_id and m.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and m.fk_marca_dispositivo_id=p_marca_dispositivo_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_variante_modelo_dispositivo_id is not null and not exists(select 1 from public.variantes_modelo_dispositivo v where v.id=p_variante_modelo_dispositivo_id and v.fk_modelo_dispositivo_id=p_modelo_dispositivo_id and v.activo) then raise exception 'INVALID_DEVICE_VARIANT'; end if;
  if p_color_dispositivo_id is not null and not exists(select 1 from public.colores_dispositivo where id=p_color_dispositivo_id and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_COLOR'; end if;
  if v_es_pc and p_color_dispositivo_id is null then raise exception 'DEVICE_COLOR_REQUIRED'; end if;
  if v_es_pc and nullif(btrim(coalesce(p_numero_serie,'')),'') is not null then raise exception 'PC_SERIAL_NOT_ALLOWED'; end if;
  if v_es_pc and (p_marca_procesador_id is null or p_familia_procesador_id is null or p_modelo_procesador_id is null) then raise exception 'PROCESSOR_REQUIRED'; end if;
  if p_modelo_procesador_id is not null and not exists(select 1 from public.modelos_procesador mp join public.familias_procesador fp on fp.id=mp.fk_familia_procesador_id where mp.id=p_modelo_procesador_id and fp.id=p_familia_procesador_id and fp.fk_marca_procesador_id=p_marca_procesador_id and mp.activo and fp.activo and (mp.alcance='GLOBAL' or mp.fk_organizacion_id=v_org)) then raise exception 'INVALID_PROCESSOR'; end if;

  if v_es_pc then
    if coalesce(p_atributos->>'case_fan_count','') !~ '^([0-9]|[1-4][0-9]|50)$' then raise exception 'INVALID_CASE_FAN_COUNT'; end if;
    if coalesce(p_atributos->>'case_has_original_power_supply','') not in ('true','false') then raise exception 'INVALID_POWER_SUPPLY_MODE'; end if;
    if p_atributos->>'case_has_original_power_supply'='true' and char_length(btrim(coalesce(p_atributos->>'included_power_supply_name',''))) not between 2 and 200 then raise exception 'INCLUDED_POWER_SUPPLY_REQUIRED'; end if;
    if p_atributos->>'case_has_original_power_supply'='true' and (nullif(p_atributos->>'external_power_supply_brand_id','') is not null or nullif(p_atributos->>'external_power_supply_model_id','') is not null) then raise exception 'DUPLICATED_POWER_SUPPLY'; end if;
    if p_atributos->>'case_has_original_power_supply'='false' and nullif(btrim(coalesce(p_atributos->>'included_power_supply_name','')),'') is not null then raise exception 'DUPLICATED_POWER_SUPPLY'; end if;
    if coalesce(p_atributos->>'graphics_mode','') not in ('INTEGRATED','DEDICATED') then raise exception 'INVALID_GRAPHICS_MODE'; end if;
    if p_atributos->>'graphics_mode'='DEDICATED' and (nullif(p_atributos->>'gpu_brand_id','') is null or nullif(p_atributos->>'gpu_model_id','') is null) then raise exception 'DEDICATED_GPU_REQUIRED'; end if;
    if p_atributos->>'graphics_mode'='INTEGRATED' and (nullif(p_atributos->>'gpu_brand_id','') is not null or nullif(p_atributos->>'gpu_model_id','') is not null) then raise exception 'DUPLICATED_GRAPHICS'; end if;
    if coalesce(p_atributos->>'cpu_cooler_mode','') not in ('ORIGINAL','EXTERNAL') then raise exception 'INVALID_CPU_COOLER_MODE'; end if;
    if p_atributos->>'cpu_cooler_mode'='EXTERNAL' and (nullif(p_atributos->>'cpu_cooler_brand_id','') is null or nullif(p_atributos->>'cpu_cooler_model_id','') is null) then raise exception 'EXTERNAL_CPU_COOLER_REQUIRED'; end if;
    if p_atributos->>'cpu_cooler_mode'='ORIGINAL' and (nullif(p_atributos->>'cpu_cooler_brand_id','') is not null or nullif(p_atributos->>'cpu_cooler_model_id','') is not null) then raise exception 'DUPLICATED_CPU_COOLER'; end if;
    if coalesce(p_atributos->>'operating_system_kind','') not in ('WINDOWS','LINUX','MACOS','OTHER','NONE') then raise exception 'INVALID_OPERATING_SYSTEM'; end if;
    if p_atributos->>'operating_system_kind'<>'NONE' and char_length(btrim(coalesce(p_atributos->>'operating_system_version',''))) not between 2 and 120 then raise exception 'OPERATING_SYSTEM_VERSION_REQUIRED'; end if;
    if p_atributos->>'operating_system_kind'='NONE' and nullif(btrim(coalesce(p_atributos->>'operating_system_version','')),'') is not null then raise exception 'INVALID_OPERATING_SYSTEM'; end if;
    if coalesce(p_atributos->>'has_wifi','') not in ('true','false') then raise exception 'INVALID_WIFI'; end if;
    if p_atributos->>'has_wifi'='true' and coalesce(p_atributos->>'wifi_mode','') not in ('INTEGRATED','EXTERNAL') then raise exception 'INVALID_WIFI_MODE'; end if;
    if p_atributos->>'wifi_mode'='EXTERNAL' and (nullif(p_atributos->>'wifi_brand_id','') is null or nullif(p_atributos->>'wifi_model_id','') is null) then raise exception 'EXTERNAL_WIFI_REQUIRED'; end if;
    if (p_atributos->>'has_wifi'='false' or p_atributos->>'wifi_mode'='INTEGRATED') and (nullif(p_atributos->>'wifi_brand_id','') is not null or nullif(p_atributos->>'wifi_model_id','') is not null) then raise exception 'DUPLICATED_WIFI'; end if;
    if coalesce(p_atributos->>'has_optical_drive','') not in ('true','false') then raise exception 'INVALID_OPTICAL_DRIVE'; end if;
  end if;

  -- Comprueba todos los pares marca/modelo de componentes sin confiar en IDs del cliente.
  for v_par in select * from (values
    ('GABINETE','case_brand_id','case_model_id'),('FUENTE_ALIMENTACION','external_power_supply_brand_id','external_power_supply_model_id'),
    ('PLACA_MADRE','motherboard_brand_id','motherboard_model_id'),('TARJETA_GRAFICA','gpu_brand_id','gpu_model_id'),
    ('COOLER_PROCESADOR','cpu_cooler_brand_id','cpu_cooler_model_id'),('ADAPTADOR_WIFI','wifi_brand_id','wifi_model_id')
  ) x(categoria,clave_marca,clave_modelo) loop
    v_marca:=nullif(p_atributos->>v_par.clave_marca,'')::uuid; v_modelo:=nullif(p_atributos->>v_par.clave_modelo,'')::uuid;
    if v_modelo is not null and v_marca is null then raise exception 'INVALID_COMPONENT_MODEL'; end if;
    if v_marca is not null and not exists(select 1 from public.marcas_componente m join public.categorias_componente_marcas cm on cm.fk_marca_componente_id=m.id join public.categorias_componente c on c.id=cm.fk_categoria_componente_id where m.id=v_marca and c.clave=v_par.categoria and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_COMPONENT_BRAND'; end if;
    if v_modelo is not null and not exists(select 1 from public.modelos_componente m join public.categorias_componente c on c.id=m.fk_categoria_componente_id where m.id=v_modelo and m.fk_marca_componente_id=v_marca and c.clave=v_par.categoria and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_COMPONENT_MODEL'; end if;
  end loop;

  insert into public.dispositivos_clientes(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,fk_variante_modelo_dispositivo_id,fk_color_dispositivo_id,numero_serie,created_by)
  values(v_org,p_cliente_id,p_tipo_dispositivo_id,p_marca_dispositivo_id,p_modelo_dispositivo_id,p_variante_modelo_dispositivo_id,p_color_dispositivo_id,nullif(btrim(p_numero_serie),''),auth.uid()) returning id into v_id;
  if p_modelo_procesador_id is not null then insert into public.procesadores_dispositivos(fk_dispositivo_cliente_id,fk_modelo_procesador_id) values(v_id,p_modelo_procesador_id); end if;

  for v_par in select key,value from jsonb_each_text(p_atributos) loop
    if v_par.value='' then continue; end if;
    select tc.id,c.tipo_campo,c.clave_fuente_datos into v_campo from public.tipos_dispositivo_campos tc join public.campos_dispositivo c on c.id=tc.fk_campo_dispositivo_id where tc.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and tc.activo and c.activo and c.clave=v_par.key;
    if not found then raise exception 'INVALID_DEVICE_FIELD'; end if;
    if v_campo.tipo_campo in ('SELECT','RADIO') and v_campo.clave_fuente_datos is null then
      select o.id into v_opcion from public.opciones_campo_dispositivo o where o.fk_campo_dispositivo_id=(select fk_campo_dispositivo_id from public.tipos_dispositivo_campos where id=v_campo.id) and o.valor=v_par.value and o.activo;
      if v_opcion is null then raise exception 'INVALID_DEVICE_FIELD_OPTION'; end if;
      insert into public.valores_campos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,fk_opcion_campo_dispositivo_id) values(v_id,v_campo.id,v_opcion);
    elsif v_campo.tipo_campo='NUMBER' then
      insert into public.valores_campos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,valor_numero) values(v_id,v_campo.id,v_par.value::numeric);
    else
      insert into public.valores_campos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,valor_texto) values(v_id,v_campo.id,btrim(v_par.value));
    end if;
  end loop;

  for v_item in select value from jsonb_array_elements(p_memorias) loop
    if coalesce(v_item->>'capacity','') !~ '^[1-9][0-9]{0,3}$' or coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]{0,2}$' then raise exception 'INVALID_MEMORY'; end if;
    insert into public.memoria_ram_dispositivo(fk_dispositivo_cliente_id,capacidad_gb,cantidad,soldada) values(v_id,(v_item->>'capacity')::integer,(v_item->>'quantity')::smallint,coalesce((v_item->>'soldered')::boolean,false));
  end loop;
  for v_item in select value from jsonb_array_elements(p_almacenamientos) loop
    if coalesce(v_item->>'capacity','') !~ '^[1-9][0-9]{0,6}$' or coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]{0,2}$' then raise exception 'INVALID_STORAGE'; end if;
    if not exists(select 1 from public.tipos_almacenamiento where id=(v_item->>'type')::uuid and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org)) then raise exception 'INVALID_STORAGE_TYPE'; end if;
    insert into public.almacenamientos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_almacenamiento_id,capacidad_gb,cantidad) values(v_id,(v_item->>'type')::uuid,(v_item->>'capacity')::integer,(v_item->>'quantity')::smallint);
  end loop;
  for v_item in select value from jsonb_array_elements(p_accesorios) loop
    if not exists(select 1 from public.accesorios_dispositivo where id=(v_item#>>'{}')::uuid and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org)) then raise exception 'INVALID_ACCESSORY'; end if;
    insert into public.dispositivos_clientes_accesorios(fk_dispositivo_cliente_id,fk_accesorio_dispositivo_id) values(v_id,(v_item#>>'{}')::uuid) on conflict do nothing;
  end loop;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DISPOSITIVO_CLIENTE_CREADO','DISPOSITIVO_CLIENTE',v_id,jsonb_build_object('modelo_procesador_id',p_modelo_procesador_id,'memorias',jsonb_array_length(p_memorias),'almacenamientos',jsonb_array_length(p_almacenamientos),'accesorios',jsonb_array_length(p_accesorios)));
  return v_id;
end $$;

-- Evita que una carrera concurrente falle cuando ambas altas representan el mismo modelo.
create or replace function public.crear_modelo_procesador(p_marca_procesador_id uuid,p_familia_procesador_id uuid,p_nombre text)
returns public.modelos_procesador language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_modelo public.modelos_procesador;
begin
  if char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_PROCESSOR'; end if;
  if not exists(select 1 from public.familias_procesador where id=p_familia_procesador_id and fk_marca_procesador_id=p_marca_procesador_id and activo) then raise exception 'INVALID_PROCESSOR_FAMILY'; end if;
  select * into v_modelo from public.modelos_procesador where fk_familia_procesador_id=p_familia_procesador_id and nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_modelo; end if;
  insert into public.modelos_procesador(fk_familia_procesador_id,nombre,alcance,fk_organizacion_id,created_by) values(p_familia_procesador_id,v_nombre,'ORGANIZACION',v_org,auth.uid()) on conflict on constraint uq_modelos_procesador_nombre_alcance do update set updated_at=now() returning * into v_modelo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MODELO_PROCESADOR_CREADO','MODELO_PROCESADOR',v_modelo.id,jsonb_build_object('familia_procesador_id',p_familia_procesador_id));
  return v_modelo;
end $$;

revoke all on function public.crear_color_dispositivo(text),public.crear_marca_componente(text,text),public.crear_modelo_componente(text,uuid,text),public.crear_tipo_almacenamiento(text),public.crear_accesorio_dispositivo(text),public.crear_dispositivo_cliente(uuid,uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.crear_color_dispositivo(text),public.crear_marca_componente(text,text),public.crear_modelo_componente(text,uuid,text),public.crear_tipo_almacenamiento(text),public.crear_accesorio_dispositivo(text),public.crear_dispositivo_cliente(uuid,uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) to authenticated;

commit;
