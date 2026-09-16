-- Reconstrucción canónica del dominio de dispositivos y recepción.
-- Los catálogos y recepciones previos eran datos de prueba autorizados para eliminar.
-- Esta migración no modifica auth ni storage.

begin;

create or replace function public.normalizar_nombre_catalogo(p_valor text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select lower(regexp_replace(btrim(p_valor), '\\s+', ' ', 'g'))
$$;

-- Las tablas legacy del dominio se eliminan juntas para evitar mantener dos fuentes de verdad.
drop table if exists public.reception_photos cascade;
drop table if exists public.reception_inspection_items cascade;
drop table if exists public.repair_device_diagnostics cascade;
drop table if exists public.repair_device_component_values cascade;
drop table if exists public.repair_device_components cascade;
drop table if exists public.customer_device_field_values cascade;
drop table if exists public.device_receptions cascade;
drop table if exists public.device_field_dependencies cascade;
drop table if exists public.device_type_fields cascade;
drop table if exists public.device_field_options cascade;
drop table if exists public.device_fields cascade;
drop table if exists public.device_form_sections cascade;
drop table if exists public.device_reception_controls cascade;
drop table if exists public.hardware_catalog_models cascade;
drop table if exists public.hardware_catalog_brands cascade;
drop table if exists public.notebook_keyboard_mount_types cascade;
drop table if exists public.memory_capacities cascade;
drop table if exists public.storage_capacities cascade;
drop table if exists public.operating_systems cascade;
drop table if exists public.device_accessories cascade;
drop table if exists public.device_lock_types cascade;
drop table if exists public.mobile_operators cascade;
drop table if exists public.customer_devices cascade;
drop table if exists public.device_model_variants cascade;
drop table if exists public.device_models cascade;
drop table if exists public.device_product_families cascade;
drop table if exists public.device_colors cascade;
drop table if exists public.device_brands cascade;
drop table if exists public.device_types cascade;

create table public.tipos_dispositivo (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_tipos_dispositivo_nombre check (char_length(btrim(nombre)) between 2 and 80),
  constraint uq_tipos_dispositivo_nombre_normalizado unique (nombre_normalizado)
);

create table public.marcas_dispositivo (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_marcas_dispositivo_nombre check (char_length(btrim(nombre)) between 2 and 80),
  constraint ck_marcas_dispositivo_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_marcas_dispositivo_nombre_alcance unique nulls not distinct (nombre_normalizado, fk_organizacion_id)
);

create table public.tipos_dispositivo_marcas (
  fk_tipo_dispositivo_id uuid not null references public.tipos_dispositivo(id) on delete restrict,
  fk_marca_dispositivo_id uuid not null references public.marcas_dispositivo(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (fk_tipo_dispositivo_id, fk_marca_dispositivo_id),
  constraint uq_tipos_dispositivo_marcas unique (fk_tipo_dispositivo_id, fk_marca_dispositivo_id)
);

create table public.modelos_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_tipo_dispositivo_id uuid not null references public.tipos_dispositivo(id) on delete restrict,
  fk_marca_dispositivo_id uuid not null references public.marcas_dispositivo(id) on delete restrict,
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_modelos_dispositivo_nombre check (char_length(btrim(nombre)) between 2 and 120),
  constraint ck_modelos_dispositivo_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint fk_modelos_dispositivo_tipo_marca foreign key (fk_tipo_dispositivo_id, fk_marca_dispositivo_id) references public.tipos_dispositivo_marcas(fk_tipo_dispositivo_id, fk_marca_dispositivo_id) on delete restrict,
  constraint uq_modelos_dispositivo_nombre_alcance unique nulls not distinct (fk_tipo_dispositivo_id, fk_marca_dispositivo_id, nombre_normalizado, fk_organizacion_id),
  constraint uq_modelos_dispositivo_integridad unique (id, fk_tipo_dispositivo_id, fk_marca_dispositivo_id)
);

create table public.variantes_modelo_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_modelo_dispositivo_id uuid not null references public.modelos_dispositivo(id) on delete restrict,
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_variantes_modelo_dispositivo_nombre check (char_length(btrim(nombre)) between 2 and 140),
  constraint uq_variantes_modelo_dispositivo_nombre unique (fk_modelo_dispositivo_id, nombre_normalizado),
  constraint uq_variantes_modelo_dispositivo_integridad unique (id, fk_modelo_dispositivo_id)
);

create table public.colores_dispositivo (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_colores_dispositivo_nombre check (char_length(btrim(nombre)) between 2 and 80),
  constraint uq_colores_dispositivo_nombre_normalizado unique (nombre_normalizado)
);

create table public.dispositivos_clientes (
  id uuid primary key default gen_random_uuid(),
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  fk_cliente_id uuid not null,
  fk_tipo_dispositivo_id uuid not null references public.tipos_dispositivo(id) on delete restrict,
  fk_marca_dispositivo_id uuid,
  fk_modelo_dispositivo_id uuid,
  fk_variante_modelo_dispositivo_id uuid,
  fk_color_dispositivo_id uuid references public.colores_dispositivo(id) on delete set null,
  numero_serie text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_dispositivos_clientes_numero_serie check (numero_serie is null or (numero_serie = btrim(numero_serie) and numero_serie <> '' and char_length(numero_serie) <= 120)),
  constraint fk_dispositivos_clientes_cliente_organizacion foreign key (fk_cliente_id, fk_organizacion_id) references public.customers(id, organization_id) on delete restrict,
  constraint fk_dispositivos_clientes_tipo_marca foreign key (fk_tipo_dispositivo_id, fk_marca_dispositivo_id) references public.tipos_dispositivo_marcas(fk_tipo_dispositivo_id, fk_marca_dispositivo_id) on delete restrict,
  constraint fk_dispositivos_clientes_modelo_tipo_marca foreign key (fk_modelo_dispositivo_id, fk_tipo_dispositivo_id, fk_marca_dispositivo_id) references public.modelos_dispositivo(id, fk_tipo_dispositivo_id, fk_marca_dispositivo_id) on delete restrict,
  constraint fk_dispositivos_clientes_variante_modelo foreign key (fk_variante_modelo_dispositivo_id, fk_modelo_dispositivo_id) references public.variantes_modelo_dispositivo(id, fk_modelo_dispositivo_id) on delete restrict,
  constraint ck_dispositivos_clientes_modelo_requiere_marca check (fk_modelo_dispositivo_id is null or fk_marca_dispositivo_id is not null),
  constraint ck_dispositivos_clientes_variante_requiere_modelo check (fk_variante_modelo_dispositivo_id is null or fk_modelo_dispositivo_id is not null),
  constraint uq_dispositivos_clientes_id_organizacion unique (id, fk_organizacion_id)
);
create index ix_dispositivos_clientes_organizacion_cliente on public.dispositivos_clientes(fk_organizacion_id, fk_cliente_id);

create table public.secciones_formulario_dispositivo (
  id uuid primary key default gen_random_uuid(),
  clave text not null,
  titulo text not null,
  descripcion text,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_secciones_formulario_dispositivo_clave check (clave ~ '^[a-z][a-z0-9_]{1,60}$'),
  constraint ck_secciones_formulario_dispositivo_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_secciones_formulario_dispositivo_clave_alcance unique nulls not distinct (clave, fk_organizacion_id)
);

create table public.campos_dispositivo (
  id uuid primary key default gen_random_uuid(),
  clave text not null,
  etiqueta text not null,
  tipo_campo text not null,
  clave_fuente_datos text,
  placeholder text,
  texto_ayuda text,
  validacion jsonb not null default '{}'::jsonb,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_campos_dispositivo_clave check (clave ~ '^[a-z][a-z0-9_]{1,60}$'),
  constraint ck_campos_dispositivo_tipo check (tipo_campo in ('TEXT','NUMBER','TEXTAREA','SELECT','MULTISELECT','CHECKBOX','RADIO','SWITCH','REPEATABLE')),
  constraint ck_campos_dispositivo_validacion check (jsonb_typeof(validacion) = 'object'),
  constraint ck_campos_dispositivo_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_campos_dispositivo_clave_alcance unique nulls not distinct (clave, fk_organizacion_id)
);

create table public.opciones_campo_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_campo_dispositivo_id uuid not null references public.campos_dispositivo(id) on delete restrict,
  valor text not null,
  etiqueta text not null,
  orden integer not null default 0,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_opciones_campo_dispositivo_valor check (valor = btrim(valor) and valor <> '' and char_length(valor) <= 160),
  constraint ck_opciones_campo_dispositivo_etiqueta check (etiqueta = btrim(etiqueta) and etiqueta <> '' and char_length(etiqueta) <= 160),
  constraint uq_opciones_campo_dispositivo_valor unique (fk_campo_dispositivo_id, valor)
);

create table public.tipos_dispositivo_campos (
  id uuid primary key default gen_random_uuid(),
  fk_tipo_dispositivo_id uuid not null references public.tipos_dispositivo(id) on delete restrict,
  fk_seccion_formulario_dispositivo_id uuid not null references public.secciones_formulario_dispositivo(id) on delete restrict,
  fk_campo_dispositivo_id uuid not null references public.campos_dispositivo(id) on delete restrict,
  orden integer not null default 0,
  obligatorio boolean not null default false,
  overrides jsonb not null default '{}'::jsonb,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint ck_tipos_dispositivo_campos_overrides check (jsonb_typeof(overrides) = 'object'),
  constraint uq_tipos_dispositivo_campos unique (fk_tipo_dispositivo_id, fk_campo_dispositivo_id),
  constraint uq_tipos_dispositivo_campos_orden unique (fk_tipo_dispositivo_id, fk_seccion_formulario_dispositivo_id, orden)
);

create table public.valores_campos_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_dispositivo_cliente_id uuid not null references public.dispositivos_clientes(id) on delete restrict,
  fk_tipo_dispositivo_campo_id uuid not null references public.tipos_dispositivo_campos(id) on delete restrict,
  valor_texto text,
  valor_numero numeric,
  valor_booleano boolean,
  valor_json jsonb,
  fk_opcion_campo_dispositivo_id uuid references public.opciones_campo_dispositivo(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_valores_campos_dispositivo_un_valor check (num_nonnulls(valor_texto, valor_numero, valor_booleano, valor_json, fk_opcion_campo_dispositivo_id) = 1),
  constraint ck_valores_campos_dispositivo_texto check (valor_texto is null or (valor_texto = btrim(valor_texto) and valor_texto <> '')),
  constraint uq_valores_campos_dispositivo_campo unique (fk_dispositivo_cliente_id, fk_tipo_dispositivo_campo_id)
);

create table public.controles_recepcion_dispositivo (
  id uuid primary key default gen_random_uuid(),
  clave text not null unique,
  etiqueta text not null,
  descripcion text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_controles_recepcion_dispositivo_clave check (clave ~ '^[a-z][a-z0-9_]{1,60}$'),
  constraint ck_controles_recepcion_dispositivo_etiqueta check (char_length(btrim(etiqueta)) between 2 and 120)
);

create table public.tipos_dispositivo_controles_recepcion (
  fk_tipo_dispositivo_id uuid not null references public.tipos_dispositivo(id) on delete restrict,
  fk_control_recepcion_dispositivo_id uuid not null references public.controles_recepcion_dispositivo(id) on delete restrict,
  orden integer not null default 0,
  obligatorio boolean not null default false,
  activo boolean not null default true,
  primary key (fk_tipo_dispositivo_id, fk_control_recepcion_dispositivo_id),
  constraint uq_tipos_dispositivo_controles_recepcion unique (fk_tipo_dispositivo_id, fk_control_recepcion_dispositivo_id)
);

create table public.recepciones_dispositivos (
  id uuid primary key default gen_random_uuid(),
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  fk_dispositivo_cliente_id uuid not null,
  problema_informado text not null,
  observaciones text,
  puntaje_condicion numeric(6,1) not null,
  condicion_calculada text not null,
  snapshot_ingreso jsonb not null default '{}'::jsonb,
  estado text not null default 'CONFIRMADA',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ck_recepciones_dispositivos_problema check (char_length(btrim(problema_informado)) between 10 and 2000),
  constraint ck_recepciones_dispositivos_observaciones check (observaciones is null or (observaciones = btrim(observaciones) and char_length(observaciones) <= 2000)),
  constraint ck_recepciones_dispositivos_puntaje check (puntaje_condicion >= 0),
  constraint ck_recepciones_dispositivos_snapshot check (jsonb_typeof(snapshot_ingreso) = 'object'),
  constraint ck_recepciones_dispositivos_estado check (estado = 'CONFIRMADA'),
  constraint fk_recepciones_dispositivos_dispositivo_organizacion foreign key (fk_dispositivo_cliente_id, fk_organizacion_id) references public.dispositivos_clientes(id, fk_organizacion_id) on delete restrict
);
create index ix_recepciones_dispositivos_organizacion_creada on public.recepciones_dispositivos(fk_organizacion_id, created_at desc);

create table public.resultados_control_recepcion (
  id uuid primary key default gen_random_uuid(),
  fk_recepcion_dispositivo_id uuid not null references public.recepciones_dispositivos(id) on delete restrict,
  fk_control_recepcion_dispositivo_id uuid not null references public.controles_recepcion_dispositivo(id) on delete restrict,
  condicion text not null,
  severidad text,
  observacion text,
  es_critico boolean not null default false,
  created_at timestamptz not null default now(),
  constraint ck_resultados_control_recepcion_condicion check (condicion in ('FUNCIONA','FUNCIONA_PARCIALMENTE','NO_FUNCIONA','NO_COMPROBABLE','BUENO','REGULAR','MALO')),
  constraint ck_resultados_control_recepcion_observacion check (observacion is null or (observacion = btrim(observacion) and char_length(observacion) <= 2000)),
  constraint uq_resultados_control_recepcion unique (fk_recepcion_dispositivo_id, fk_control_recepcion_dispositivo_id)
);

create table public.fotos_recepcion (
  id uuid primary key default gen_random_uuid(),
  fk_recepcion_dispositivo_id uuid not null references public.recepciones_dispositivos(id) on delete restrict,
  ruta_storage text not null,
  descripcion text,
  clave_control text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ck_fotos_recepcion_ruta check (ruta_storage ~ '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[^/].*$'),
  constraint ck_fotos_recepcion_descripcion check (descripcion is null or (descripcion = btrim(descripcion) and char_length(descripcion) <= 300))
);

create table public.diagnosticos_dispositivo (
  id uuid primary key default gen_random_uuid(),
  fk_organizacion_id uuid not null references public.organizations(id) on delete restrict,
  fk_recepcion_dispositivo_id uuid not null references public.recepciones_dispositivos(id) on delete restrict,
  diagnostico text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ck_diagnosticos_dispositivo_texto check (char_length(btrim(diagnostico)) between 1 and 4000)
);

-- RLS: ningún catálogo privado o registro operativo cruza organizaciones.
alter table public.tipos_dispositivo enable row level security;
alter table public.marcas_dispositivo enable row level security;
alter table public.tipos_dispositivo_marcas enable row level security;
alter table public.modelos_dispositivo enable row level security;
alter table public.variantes_modelo_dispositivo enable row level security;
alter table public.colores_dispositivo enable row level security;
alter table public.dispositivos_clientes enable row level security;
alter table public.secciones_formulario_dispositivo enable row level security;
alter table public.campos_dispositivo enable row level security;
alter table public.opciones_campo_dispositivo enable row level security;
alter table public.tipos_dispositivo_campos enable row level security;
alter table public.valores_campos_dispositivo enable row level security;
alter table public.controles_recepcion_dispositivo enable row level security;
alter table public.tipos_dispositivo_controles_recepcion enable row level security;
alter table public.recepciones_dispositivos enable row level security;
alter table public.resultados_control_recepcion enable row level security;
alter table public.fotos_recepcion enable row level security;
alter table public.diagnosticos_dispositivo enable row level security;

create policy tipos_dispositivo_lectura on public.tipos_dispositivo for select using (activo);
create policy marcas_dispositivo_lectura on public.marcas_dispositivo for select using (activo and (alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()));
create policy modelos_dispositivo_lectura on public.modelos_dispositivo for select using (activo and (alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()));
create policy colores_dispositivo_lectura on public.colores_dispositivo for select using (activo);
create policy variantes_modelo_dispositivo_lectura on public.variantes_modelo_dispositivo for select using (activo);
create policy tipos_dispositivo_marcas_lectura on public.tipos_dispositivo_marcas for select using (exists (select 1 from public.marcas_dispositivo m where m.id = fk_marca_dispositivo_id and (m.alcance = 'GLOBAL' or m.fk_organizacion_id = public.current_organization_id())));
create policy dispositivos_clientes_organizacion on public.dispositivos_clientes for all using (fk_organizacion_id = public.current_organization_id()) with check (fk_organizacion_id = public.current_organization_id());
create policy secciones_formulario_dispositivo_lectura on public.secciones_formulario_dispositivo for select using (activo and (alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()));
create policy campos_dispositivo_lectura on public.campos_dispositivo for select using (activo and (alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()));
create policy opciones_campo_dispositivo_lectura on public.opciones_campo_dispositivo for select using (activo);
create policy tipos_dispositivo_campos_lectura on public.tipos_dispositivo_campos for select using (activo);
create policy valores_campos_dispositivo_organizacion on public.valores_campos_dispositivo for select using (exists (select 1 from public.dispositivos_clientes d where d.id = fk_dispositivo_cliente_id and d.fk_organizacion_id = public.current_organization_id()));
create policy controles_recepcion_dispositivo_lectura on public.controles_recepcion_dispositivo for select using (activo);
create policy tipos_dispositivo_controles_recepcion_lectura on public.tipos_dispositivo_controles_recepcion for select using (activo);
create policy recepciones_dispositivos_organizacion on public.recepciones_dispositivos for all using (fk_organizacion_id = public.current_organization_id()) with check (fk_organizacion_id = public.current_organization_id());
create policy resultados_control_recepcion_organizacion on public.resultados_control_recepcion for select using (exists (select 1 from public.recepciones_dispositivos r where r.id = fk_recepcion_dispositivo_id and r.fk_organizacion_id = public.current_organization_id()));
create policy fotos_recepcion_organizacion on public.fotos_recepcion for all using (exists (select 1 from public.recepciones_dispositivos r where r.id = fk_recepcion_dispositivo_id and r.fk_organizacion_id = public.current_organization_id())) with check (exists (select 1 from public.recepciones_dispositivos r where r.id = fk_recepcion_dispositivo_id and r.fk_organizacion_id = public.current_organization_id()));
create policy diagnosticos_dispositivo_organizacion on public.diagnosticos_dispositivo for all using (fk_organizacion_id = public.current_organization_id()) with check (fk_organizacion_id = public.current_organization_id());

-- Las mutaciones del dominio pasan por RPC transaccionales. La organización y
-- el rol se derivan de la sesión; nunca se reciben desde el cliente.
create or replace function public.crear_marca_dispositivo(p_nombre text, p_tipo_dispositivo_id uuid)
returns public.marcas_dispositivo
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.assert_reception_owner(); v_marca public.marcas_dispositivo;
begin
  if not exists (select 1 from public.tipos_dispositivo where id = p_tipo_dispositivo_id and activo) then raise exception 'INVALID_DEVICE_TYPE'; end if;
  insert into public.marcas_dispositivo(nombre, alcance, fk_organizacion_id, created_by)
  values (regexp_replace(btrim(p_nombre), '\\s+', ' ', 'g'), 'ORGANIZACION', v_org, auth.uid())
  on conflict (nombre_normalizado, fk_organizacion_id) do update set updated_at = now()
  returning * into v_marca;
  insert into public.tipos_dispositivo_marcas(fk_tipo_dispositivo_id, fk_marca_dispositivo_id)
  values (p_tipo_dispositivo_id, v_marca.id) on conflict do nothing;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_org, auth.uid(), 'MARCA_DISPOSITIVO_CREADA', 'MARCA_DISPOSITIVO', v_marca.id, jsonb_build_object('tipo_dispositivo_id', p_tipo_dispositivo_id));
  return v_marca;
end $$;

create or replace function public.crear_modelo_dispositivo(p_nombre text, p_tipo_dispositivo_id uuid, p_marca_dispositivo_id uuid)
returns public.modelos_dispositivo
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.assert_reception_owner(); v_modelo public.modelos_dispositivo;
begin
  if not exists (select 1 from public.tipos_dispositivo_marcas tm join public.marcas_dispositivo m on m.id = tm.fk_marca_dispositivo_id where tm.fk_tipo_dispositivo_id = p_tipo_dispositivo_id and tm.fk_marca_dispositivo_id = p_marca_dispositivo_id and m.activo and (m.alcance = 'GLOBAL' or m.fk_organizacion_id = v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  insert into public.modelos_dispositivo(fk_tipo_dispositivo_id, fk_marca_dispositivo_id, nombre, alcance, fk_organizacion_id, created_by)
  values (p_tipo_dispositivo_id, p_marca_dispositivo_id, regexp_replace(btrim(p_nombre), '\\s+', ' ', 'g'), 'ORGANIZACION', v_org, auth.uid())
  on conflict (fk_tipo_dispositivo_id, fk_marca_dispositivo_id, nombre_normalizado, fk_organizacion_id) do update set updated_at = now()
  returning * into v_modelo;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_org, auth.uid(), 'MODELO_DISPOSITIVO_CREADO', 'MODELO_DISPOSITIVO', v_modelo.id, jsonb_build_object('tipo_dispositivo_id', p_tipo_dispositivo_id, 'marca_dispositivo_id', p_marca_dispositivo_id));
  return v_modelo;
end $$;

create or replace function public.crear_color_dispositivo(p_nombre text)
returns public.colores_dispositivo
language plpgsql security definer set search_path = '' as $$
declare v_color public.colores_dispositivo;
begin
  perform public.assert_reception_owner();
  insert into public.colores_dispositivo(nombre, created_by) values (regexp_replace(btrim(p_nombre), '\\s+', ' ', 'g'), auth.uid())
  on conflict (nombre_normalizado) do update set updated_at = now() returning * into v_color;
  return v_color;
end $$;

create or replace function public.crear_dispositivo_cliente(p_cliente_id uuid, p_tipo_dispositivo_id uuid, p_marca_dispositivo_id uuid, p_modelo_dispositivo_id uuid default null, p_variante_modelo_dispositivo_id uuid default null, p_color_dispositivo_id uuid default null, p_numero_serie text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.assert_reception_owner(); v_id uuid;
begin
  if not exists (select 1 from public.customers where id = p_cliente_id and organization_id = v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  insert into public.dispositivos_clientes(fk_organizacion_id, fk_cliente_id, fk_tipo_dispositivo_id, fk_marca_dispositivo_id, fk_modelo_dispositivo_id, fk_variante_modelo_dispositivo_id, fk_color_dispositivo_id, numero_serie, created_by)
  values (v_org, p_cliente_id, p_tipo_dispositivo_id, p_marca_dispositivo_id, p_modelo_dispositivo_id, p_variante_modelo_dispositivo_id, p_color_dispositivo_id, nullif(btrim(p_numero_serie), ''), auth.uid()) returning id into v_id;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata) values (v_org, auth.uid(), 'DISPOSITIVO_CLIENTE_CREADO', 'DISPOSITIVO_CLIENTE', v_id, '{}'::jsonb);
  return v_id;
end $$;

create or replace function public.confirmar_recepcion_dispositivo(p_dispositivo_cliente_id uuid, p_problema_informado text, p_observaciones text, p_resultados jsonb)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.assert_reception_owner(); v_id uuid; v_item jsonb;
begin
  if jsonb_typeof(p_resultados) <> 'array' then raise exception 'INVALID_INSPECTION'; end if;
  insert into public.recepciones_dispositivos(fk_organizacion_id, fk_dispositivo_cliente_id, problema_informado, observaciones, puntaje_condicion, condicion_calculada, snapshot_ingreso, created_by)
  values (v_org, p_dispositivo_cliente_id, regexp_replace(btrim(p_problema_informado), '\\s+', ' ', 'g'), nullif(regexp_replace(btrim(coalesce(p_observaciones, '')), '\\s+', ' ', 'g'), ''), 0, 'No comprobable', '{}'::jsonb, auth.uid()) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_resultados) loop
    insert into public.resultados_control_recepcion(fk_recepcion_dispositivo_id, fk_control_recepcion_dispositivo_id, condicion, observacion)
    select v_id, c.id,
      case coalesce(v_item->>'condition','') when 'NOT_WORKING' then 'NO_FUNCIONA' when 'NOT_VERIFIABLE' then 'NO_COMPROBABLE' else 'BUENO' end,
      nullif(btrim(v_item->>'observation'), '')
    from public.controles_recepcion_dispositivo c
    join public.tipos_dispositivo_controles_recepcion tc on tc.fk_control_recepcion_dispositivo_id = c.id and tc.activo
    join public.dispositivos_clientes d on d.id = p_dispositivo_cliente_id and d.fk_tipo_dispositivo_id = tc.fk_tipo_dispositivo_id and d.fk_organizacion_id = v_org
    where c.clave = v_item->>'key'
    on conflict (fk_recepcion_dispositivo_id, fk_control_recepcion_dispositivo_id) do nothing;
  end loop;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata) values (v_org, auth.uid(), 'RECEPCION_DISPOSITIVO_CONFIRMADA', 'RECEPCION_DISPOSITIVO', v_id, '{}'::jsonb);
  return v_id;
end $$;

-- Sólo existen los tipos solicitados. No se insertan marcas, modelos, colores, campos ni controles.
insert into public.tipos_dispositivo(nombre) values ('PC de escritorio'), ('Notebook');

commit;
