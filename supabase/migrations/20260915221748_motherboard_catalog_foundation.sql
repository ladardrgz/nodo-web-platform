-- Motherboard catalog is a distinct hardware domain. It deliberately does not
-- reuse device_brands: a board manufacturer is not a customer-device brand.
create table public.motherboard_manufacturers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  normalized_name text generated always as (public.normalizar_nombre_catalogo(name)) stored,
  alcance text not null default 'GLOBAL',
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_motherboard_manufacturers_scope check ((alcance='GLOBAL' and fk_organizacion_id is null) or (alcance='ORGANIZACION' and fk_organizacion_id is not null)),
  constraint ck_motherboard_manufacturers_name check (char_length(btrim(name)) between 2 and 120),
  constraint uq_motherboard_manufacturers_name_scope unique nulls not distinct (normalized_name,fk_organizacion_id)
);

create table public.motherboard_models (
  id uuid primary key default gen_random_uuid(),
  motherboard_manufacturer_id uuid not null references public.motherboard_manufacturers(id) on delete restrict,
  name text not null,
  normalized_name text generated always as (public.normalizar_nombre_catalogo(name)) stored,
  alcance text not null default 'GLOBAL',
  fk_organizacion_id uuid references public.organizations(id) on delete restrict,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_motherboard_models_scope check ((alcance='GLOBAL' and fk_organizacion_id is null) or (alcance='ORGANIZACION' and fk_organizacion_id is not null)),
  constraint ck_motherboard_models_name check (char_length(btrim(name)) between 2 and 200),
  constraint uq_motherboard_models_name_scope unique nulls not distinct (motherboard_manufacturer_id,normalized_name,fk_organizacion_id),
  constraint uq_motherboard_models_id_manufacturer unique (id,motherboard_manufacturer_id)
);

create table public.motherboard_model_device_types (
  motherboard_model_id uuid not null references public.motherboard_models(id) on delete restrict,
  device_type_id uuid not null references public.device_types(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (motherboard_model_id,device_type_id)
);
create index ix_motherboard_model_device_types_device_type on public.motherboard_model_device_types(device_type_id,motherboard_model_id);

-- Current installed board only. It remains nullable for unknown/pending boards;
-- no free text is introduced and no legacy history is overwritten.
alter table public.customer_devices add column fk_motherboard_model_id uuid;
alter table public.customer_devices add constraint fk_customer_devices_motherboard_model_type
  foreign key (fk_motherboard_model_id,fk_tipo_dispositivo_id)
  references public.motherboard_model_device_types(motherboard_model_id,device_type_id) on delete restrict;
create index ix_customer_devices_motherboard_model on public.customer_devices(fk_motherboard_model_id) where fk_motherboard_model_id is not null;

alter table public.motherboard_manufacturers enable row level security;
alter table public.motherboard_models enable row level security;
alter table public.motherboard_model_device_types enable row level security;
revoke all on public.motherboard_manufacturers,public.motherboard_models,public.motherboard_model_device_types from anon,authenticated;
grant select on public.motherboard_manufacturers,public.motherboard_models,public.motherboard_model_device_types to authenticated;
create policy motherboard_manufacturers_read on public.motherboard_manufacturers for select to authenticated using (is_active and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id()));
create policy motherboard_models_read on public.motherboard_models for select to authenticated using (is_active and (alcance='GLOBAL' or fk_organizacion_id=public.current_organization_id()));
create policy motherboard_model_device_types_read on public.motherboard_model_device_types for select to authenticated using (exists(select 1 from public.motherboard_models m where m.id=motherboard_model_id and m.is_active and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())));

comment on table public.motherboard_manufacturers is 'Catálogo híbrido de fabricantes de placas madre; los datos iniciales son GLOBAL.';
comment on table public.motherboard_models is 'Catálogo híbrido de modelos comerciales de placas madre; conserva nombres como Logic Board.';
comment on column public.customer_devices.fk_motherboard_model_id is 'Motherboard instalada actualmente; NULL representa desconocida o pendiente de catalogar.';
