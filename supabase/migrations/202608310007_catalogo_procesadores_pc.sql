begin;

create table public.marcas_procesador (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_marcas_procesador_nombre check (char_length(btrim(nombre)) between 2 and 80),
  constraint uq_marcas_procesador_nombre_normalizado unique (nombre_normalizado)
);

create table public.familias_procesador (
  id uuid primary key default gen_random_uuid(),
  fk_marca_procesador_id uuid not null,
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fk_familias_procesador_marca foreign key (fk_marca_procesador_id) references public.marcas_procesador(id) on delete restrict,
  constraint ck_familias_procesador_nombre check (char_length(btrim(nombre)) between 2 and 80),
  constraint uq_familias_procesador_nombre unique (fk_marca_procesador_id, nombre_normalizado),
  constraint uq_familias_procesador_integridad unique (id, fk_marca_procesador_id)
);

create table public.modelos_procesador (
  id uuid primary key default gen_random_uuid(),
  fk_familia_procesador_id uuid not null references public.familias_procesador(id) on delete restrict,
  nombre text not null,
  nombre_normalizado text generated always as (public.normalizar_nombre_catalogo(nombre)) stored,
  alcance text not null,
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  activo boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_modelos_procesador_nombre check (char_length(btrim(nombre)) between 2 and 120),
  constraint ck_modelos_procesador_alcance check ((alcance = 'GLOBAL' and fk_organizacion_id is null) or (alcance = 'ORGANIZACION' and fk_organizacion_id is not null)),
  constraint uq_modelos_procesador_nombre_alcance unique nulls not distinct (fk_familia_procesador_id, nombre_normalizado, fk_organizacion_id),
  constraint uq_modelos_procesador_integridad unique (id, fk_familia_procesador_id)
);

create table public.procesadores_dispositivos (
  id uuid primary key default gen_random_uuid(),
  fk_dispositivo_cliente_id uuid not null references public.dispositivos_clientes(id) on delete restrict,
  fk_modelo_procesador_id uuid not null references public.modelos_procesador(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_procesadores_dispositivos_dispositivo unique (fk_dispositivo_cliente_id)
);

create index ix_familias_procesador_marca on public.familias_procesador(fk_marca_procesador_id, nombre_normalizado);
create index ix_modelos_procesador_familia on public.modelos_procesador(fk_familia_procesador_id, nombre_normalizado);

alter table public.marcas_procesador enable row level security;
alter table public.familias_procesador enable row level security;
alter table public.modelos_procesador enable row level security;
alter table public.procesadores_dispositivos enable row level security;

create policy marcas_procesador_lectura on public.marcas_procesador for select to authenticated using (activo);
create policy familias_procesador_lectura on public.familias_procesador for select to authenticated using (activo);
create policy modelos_procesador_lectura on public.modelos_procesador for select to authenticated using (activo and (alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()));
create policy procesadores_dispositivos_lectura on public.procesadores_dispositivos for select to authenticated using (exists (select 1 from public.dispositivos_clientes d where d.id = fk_dispositivo_cliente_id and d.fk_organizacion_id = public.current_organization_id()));

revoke insert, update, delete on table public.marcas_procesador, public.familias_procesador, public.modelos_procesador, public.procesadores_dispositivos from anon, authenticated;

insert into public.marcas_procesador(nombre) values ('AMD'), ('Intel');

insert into public.familias_procesador(fk_marca_procesador_id, nombre)
select m.id, f.nombre
from (values
  ('AMD','Athlon'),('AMD','Ryzen 3'),('AMD','Ryzen 5'),('AMD','Ryzen 7'),('AMD','Ryzen 9'),('AMD','FX'),('AMD','A-Series'),
  ('Intel','Celeron'),('Intel','Pentium'),('Intel','Core i3'),('Intel','Core i5'),('Intel','Core i7'),('Intel','Core i9'),('Intel','Core Ultra 5'),('Intel','Core Ultra 7'),('Intel','Core Ultra 9')
) as f(marca, nombre)
join public.marcas_procesador m on m.nombre_normalizado = public.normalizar_nombre_catalogo(f.marca);

insert into public.modelos_procesador(fk_familia_procesador_id, nombre, alcance)
select f.id, datos.modelo, 'GLOBAL'
from (values
  ('AMD','Athlon','200GE'),('AMD','Athlon','220GE'),('AMD','Athlon','240GE'),('AMD','Athlon','3000G'),('AMD','Athlon','300GE'),
  ('AMD','Ryzen 3','1200'),('AMD','Ryzen 3','2200G'),('AMD','Ryzen 3','3200G'),('AMD','Ryzen 3','3100'),('AMD','Ryzen 3','4100'),('AMD','Ryzen 3','4300G'),('AMD','Ryzen 3','5300G'),
  ('AMD','Ryzen 5','1600'),('AMD','Ryzen 5','2600'),('AMD','Ryzen 5','3400G'),('AMD','Ryzen 5','3500'),('AMD','Ryzen 5','3600'),('AMD','Ryzen 5','4500'),('AMD','Ryzen 5','4600G'),('AMD','Ryzen 5','5500'),('AMD','Ryzen 5','5600'),('AMD','Ryzen 5','5600G'),('AMD','Ryzen 5','5600X'),('AMD','Ryzen 5','7500F'),('AMD','Ryzen 5','7600'),('AMD','Ryzen 5','7600X'),('AMD','Ryzen 5','8500G'),('AMD','Ryzen 5','8600G'),('AMD','Ryzen 5','9600X'),
  ('AMD','Ryzen 7','1700'),('AMD','Ryzen 7','2700'),('AMD','Ryzen 7','2700X'),('AMD','Ryzen 7','3700X'),('AMD','Ryzen 7','3800X'),('AMD','Ryzen 7','4700G'),('AMD','Ryzen 7','5700G'),('AMD','Ryzen 7','5700X'),('AMD','Ryzen 7','5800X'),('AMD','Ryzen 7','5800X3D'),('AMD','Ryzen 7','7700'),('AMD','Ryzen 7','7700X'),('AMD','Ryzen 7','7800X3D'),('AMD','Ryzen 7','8700G'),('AMD','Ryzen 7','9700X'),('AMD','Ryzen 7','9800X3D'),
  ('AMD','Ryzen 9','3900X'),('AMD','Ryzen 9','3950X'),('AMD','Ryzen 9','5900X'),('AMD','Ryzen 9','5950X'),('AMD','Ryzen 9','7900'),('AMD','Ryzen 9','7900X'),('AMD','Ryzen 9','7900X3D'),('AMD','Ryzen 9','7950X'),('AMD','Ryzen 9','7950X3D'),('AMD','Ryzen 9','9900X'),('AMD','Ryzen 9','9950X'),
  ('AMD','FX','FX-4300'),('AMD','FX','FX-6300'),('AMD','FX','FX-8320'),('AMD','FX','FX-8350'),
  ('AMD','A-Series','A4-6300'),('AMD','A-Series','A6-7400K'),('AMD','A-Series','A8-7600'),('AMD','A-Series','A10-7860K'),('AMD','A-Series','A10-9700'),('AMD','A-Series','A12-9800'),
  ('Intel','Celeron','G1610'),('Intel','Celeron','G1820'),('Intel','Celeron','G1840'),('Intel','Celeron','G3900'),('Intel','Celeron','G3930'),('Intel','Celeron','G4900'),('Intel','Celeron','G4930'),('Intel','Celeron','G5900'),('Intel','Celeron','G5905'),('Intel','Celeron','G6900'),
  ('Intel','Pentium','G2020'),('Intel','Pentium','G2030'),('Intel','Pentium','G3220'),('Intel','Pentium','G3250'),('Intel','Pentium','G3258'),('Intel','Pentium','G4400'),('Intel','Pentium','G4560'),('Intel','Pentium','G5400'),('Intel','Pentium','G5420'),('Intel','Pentium','G6400'),('Intel','Pentium','G6405'),('Intel','Pentium','G7400'),
  ('Intel','Core i3','i3-2100'),('Intel','Core i3','i3-3220'),('Intel','Core i3','i3-4130'),('Intel','Core i3','i3-4170'),('Intel','Core i3','i3-6100'),('Intel','Core i3','i3-7100'),('Intel','Core i3','i3-8100'),('Intel','Core i3','i3-9100'),('Intel','Core i3','i3-10100'),('Intel','Core i3','i3-10100F'),('Intel','Core i3','i3-12100'),('Intel','Core i3','i3-12100F'),('Intel','Core i3','i3-13100'),('Intel','Core i3','i3-13100F'),('Intel','Core i3','i3-14100'),('Intel','Core i3','i3-14100F'),
  ('Intel','Core i5','i5-2400'),('Intel','Core i5','i5-2500'),('Intel','Core i5','i5-3470'),('Intel','Core i5','i5-3570'),('Intel','Core i5','i5-4460'),('Intel','Core i5','i5-4590'),('Intel','Core i5','i5-6400'),('Intel','Core i5','i5-6500'),('Intel','Core i5','i5-7400'),('Intel','Core i5','i5-7500'),('Intel','Core i5','i5-8400'),('Intel','Core i5','i5-9400F'),('Intel','Core i5','i5-10400'),('Intel','Core i5','i5-10400F'),('Intel','Core i5','i5-11400'),('Intel','Core i5','i5-11400F'),('Intel','Core i5','i5-12400'),('Intel','Core i5','i5-12400F'),('Intel','Core i5','i5-13400'),('Intel','Core i5','i5-13400F'),('Intel','Core i5','i5-14400'),('Intel','Core i5','i5-14400F'),
  ('Intel','Core i7','i7-2600'),('Intel','Core i7','i7-3770'),('Intel','Core i7','i7-4770'),('Intel','Core i7','i7-4790'),('Intel','Core i7','i7-6700'),('Intel','Core i7','i7-7700'),('Intel','Core i7','i7-8700'),('Intel','Core i7','i7-9700'),('Intel','Core i7','i7-10700'),('Intel','Core i7','i7-11700'),('Intel','Core i7','i7-12700'),('Intel','Core i7','i7-13700'),('Intel','Core i7','i7-14700'),
  ('Intel','Core i9','i9-9900K'),('Intel','Core i9','i9-10900K'),('Intel','Core i9','i9-11900K'),('Intel','Core i9','i9-12900K'),('Intel','Core i9','i9-13900K'),('Intel','Core i9','i9-14900K'),
  ('Intel','Core Ultra 5','225'),('Intel','Core Ultra 5','225F'),('Intel','Core Ultra 5','235'),('Intel','Core Ultra 5','245K'),('Intel','Core Ultra 5','245KF'),
  ('Intel','Core Ultra 7','265'),('Intel','Core Ultra 7','265F'),('Intel','Core Ultra 7','265K'),('Intel','Core Ultra 7','265KF'),
  ('Intel','Core Ultra 9','285K')
) as datos(marca, familia, modelo)
join public.marcas_procesador m on m.nombre_normalizado = public.normalizar_nombre_catalogo(datos.marca)
join public.familias_procesador f on f.fk_marca_procesador_id = m.id and f.nombre_normalizado = public.normalizar_nombre_catalogo(datos.familia);

insert into public.secciones_formulario_dispositivo(clave, titulo, descripcion, alcance)
values ('procesador', 'Procesador', 'Catálogo reutilizable organizado por marca, familia y modelo.', 'GLOBAL')
on conflict (clave, fk_organizacion_id) do update set titulo = excluded.titulo, descripcion = excluded.descripcion, activo = true;

insert into public.campos_dispositivo(clave, etiqueta, tipo_campo, clave_fuente_datos, placeholder, alcance)
values
  ('processor_brand_id', 'Marca del procesador', 'SELECT', 'hardware_processor_brand', 'Seleccionar marca', 'GLOBAL'),
  ('processor_family_id', 'Familia del procesador', 'SELECT', 'hardware_processor_family', 'Seleccionar familia', 'GLOBAL'),
  ('processor_model_id', 'Modelo del procesador', 'SELECT', 'hardware_processor_model', 'Seleccionar modelo', 'GLOBAL')
on conflict (clave, fk_organizacion_id) do update set etiqueta = excluded.etiqueta, tipo_campo = excluded.tipo_campo, clave_fuente_datos = excluded.clave_fuente_datos, placeholder = excluded.placeholder, activo = true;

insert into public.tipos_dispositivo_campos(fk_tipo_dispositivo_id, fk_seccion_formulario_dispositivo_id, fk_campo_dispositivo_id, orden, obligatorio)
select t.id, s.id, c.id, datos.orden, true
from (values ('processor_brand_id',10),('processor_family_id',20),('processor_model_id',30)) as datos(clave, orden)
join public.tipos_dispositivo t on t.nombre_normalizado = 'pc'
join public.secciones_formulario_dispositivo s on s.clave = 'procesador' and s.alcance = 'GLOBAL'
join public.campos_dispositivo c on c.clave = datos.clave and c.alcance = 'GLOBAL'
on conflict (fk_tipo_dispositivo_id, fk_campo_dispositivo_id) do update set fk_seccion_formulario_dispositivo_id = excluded.fk_seccion_formulario_dispositivo_id, orden = excluded.orden, obligatorio = true, activo = true;

drop function if exists public.crear_dispositivo_cliente(uuid, uuid, uuid, uuid, uuid, uuid, text);
create function public.crear_dispositivo_cliente(
  p_cliente_id uuid,
  p_tipo_dispositivo_id uuid,
  p_marca_dispositivo_id uuid,
  p_modelo_dispositivo_id uuid default null,
  p_variante_modelo_dispositivo_id uuid default null,
  p_color_dispositivo_id uuid default null,
  p_numero_serie text default null,
  p_marca_procesador_id uuid default null,
  p_familia_procesador_id uuid default null,
  p_modelo_procesador_id uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.assert_reception_owner(); v_id uuid; v_es_pc boolean;
begin
  if not exists (select 1 from public.customers where id = p_cliente_id and organization_id = v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  select nombre_normalizado = 'pc' into v_es_pc from public.tipos_dispositivo where id = p_tipo_dispositivo_id and activo;
  if v_es_pc is null then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if not exists (select 1 from public.tipos_dispositivo_marcas tm join public.marcas_dispositivo m on m.id=tm.fk_marca_dispositivo_id where tm.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and tm.fk_marca_dispositivo_id=p_marca_dispositivo_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if p_modelo_dispositivo_id is not null and not exists (select 1 from public.modelos_dispositivo m where m.id=p_modelo_dispositivo_id and m.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and m.fk_marca_dispositivo_id=p_marca_dispositivo_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if v_es_pc and (p_marca_procesador_id is null or p_familia_procesador_id is null or p_modelo_procesador_id is null) then raise exception 'PROCESSOR_REQUIRED'; end if;
  if p_modelo_procesador_id is not null and not exists (
    select 1 from public.modelos_procesador mp
    join public.familias_procesador fp on fp.id=mp.fk_familia_procesador_id
    where mp.id=p_modelo_procesador_id and fp.id=p_familia_procesador_id and fp.fk_marca_procesador_id=p_marca_procesador_id
      and mp.activo and fp.activo and (mp.alcance='GLOBAL' or mp.fk_organizacion_id=v_org)
  ) then raise exception 'INVALID_PROCESSOR'; end if;
  insert into public.dispositivos_clientes(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,fk_variante_modelo_dispositivo_id,fk_color_dispositivo_id,numero_serie,created_by)
  values(v_org,p_cliente_id,p_tipo_dispositivo_id,p_marca_dispositivo_id,p_modelo_dispositivo_id,p_variante_modelo_dispositivo_id,p_color_dispositivo_id,nullif(btrim(p_numero_serie),''),auth.uid()) returning id into v_id;
  if p_modelo_procesador_id is not null then insert into public.procesadores_dispositivos(fk_dispositivo_cliente_id,fk_modelo_procesador_id) values(v_id,p_modelo_procesador_id); end if;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DISPOSITIVO_CLIENTE_CREADO','DISPOSITIVO_CLIENTE',v_id,jsonb_build_object('modelo_procesador_id',p_modelo_procesador_id));
  return v_id;
end $$;

create function public.crear_modelo_procesador(p_marca_procesador_id uuid, p_familia_procesador_id uuid, p_nombre text)
returns public.modelos_procesador
language plpgsql security definer set search_path = '' as $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(p_nombre),'\s+',' ','g'); v_modelo public.modelos_procesador;
begin
  if char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_PROCESSOR'; end if;
  if not exists(select 1 from public.familias_procesador where id=p_familia_procesador_id and fk_marca_procesador_id=p_marca_procesador_id and activo) then raise exception 'INVALID_PROCESSOR_FAMILY'; end if;
  select * into v_modelo from public.modelos_procesador where fk_familia_procesador_id=p_familia_procesador_id and nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_modelo; end if;
  insert into public.modelos_procesador(fk_familia_procesador_id,nombre,alcance,fk_organizacion_id,created_by) values(p_familia_procesador_id,v_nombre,'ORGANIZACION',v_org,auth.uid()) returning * into v_modelo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MODELO_PROCESADOR_CREADO','MODELO_PROCESADOR',v_modelo.id,jsonb_build_object('familia_procesador_id',p_familia_procesador_id));
  return v_modelo;
end $$;

revoke all on function public.crear_dispositivo_cliente(uuid,uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,uuid) from public,anon;
revoke all on function public.crear_modelo_procesador(uuid,uuid,text) from public,anon;
grant execute on function public.crear_dispositivo_cliente(uuid,uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,uuid) to authenticated;
grant execute on function public.crear_modelo_procesador(uuid,uuid,text) to authenticated;

commit;
