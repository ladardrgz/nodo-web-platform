-- Núcleo de inventario multiempresa para talleres de servicio técnico.
create type public.inventory_movement_type as enum ('IN', 'OUT', 'ADJUSTMENT');

create table public.inventory_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 100),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (normalized_name)
);

create table public.inventory_brands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, normalized_name)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  legal_name text check (legal_name is null or char_length(btrim(legal_name)) between 2 and 160),
  phone text check (phone is null or char_length(btrim(phone)) between 6 and 30),
  email text check (email is null or char_length(btrim(email)) between 3 and 254),
  website text check (website is null or char_length(btrim(website)) between 8 and 500),
  notes text check (notes is null or char_length(notes) <= 2000),
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  category_id uuid not null references public.inventory_categories(id) on delete restrict,
  brand_id uuid,
  preferred_supplier_id uuid,
  sku text check (sku is null or char_length(btrim(sku)) between 1 and 80),
  normalized_sku text generated always as (upper(btrim(sku))) stored,
  name text not null check (char_length(btrim(name)) between 2 and 160),
  normalized_name text generated always as (public.normalize_catalog_name(name)) stored,
  description text check (description is null or char_length(description) <= 2000),
  cost numeric(14,2) not null default 0 check (cost >= 0),
  sale_price numeric(14,2) not null default 0 check (sale_price >= 0),
  current_stock numeric(14,3) not null default 0 check (current_stock >= 0),
  minimum_stock numeric(14,3) not null default 0 check (minimum_stock >= 0),
  unit text not null default 'UNIT' check (unit ~ '^[A-Z][A-Z0-9_]{0,19}$'),
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  constraint inventory_items_brand_organization_fk
    foreign key (brand_id, organization_id)
    references public.inventory_brands(id, organization_id) on delete restrict,
  constraint inventory_items_supplier_organization_fk
    foreign key (preferred_supplier_id, organization_id)
    references public.suppliers(id, organization_id) on delete restrict
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  inventory_item_id uuid not null,
  movement_type public.inventory_movement_type not null,
  quantity_delta numeric(14,3) not null,
  stock_before numeric(14,3) not null check (stock_before >= 0),
  stock_after numeric(14,3) not null check (stock_after >= 0),
  unit_cost numeric(14,2) check (unit_cost is null or unit_cost >= 0),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  reference_type text check (
    reference_type is null
    or reference_type ~ '^[A-Z][A-Z0-9_]{1,49}$'
  ),
  reference_id uuid,
  actor_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint inventory_movements_delta_type_check check (
    (movement_type = 'IN' and quantity_delta > 0)
    or (movement_type = 'OUT' and quantity_delta < 0)
    or (movement_type = 'ADJUSTMENT' and quantity_delta <> 0)
  ),
  constraint inventory_movements_reference_pair_check check (
    (reference_type is null and reference_id is null)
    or (reference_type is not null and reference_id is not null)
  ),
  constraint inventory_movements_balance_check check (
    stock_after = stock_before + quantity_delta
  ),
  foreign key (inventory_item_id, organization_id)
    references public.inventory_items(id, organization_id) on delete restrict
);

create index inventory_categories_active_name_idx
  on public.inventory_categories (is_active, name);
create index inventory_brands_organization_active_idx
  on public.inventory_brands (organization_id, is_active, name);
create index suppliers_organization_active_idx
  on public.suppliers (organization_id, is_active, normalized_name);
create unique index inventory_items_organization_sku_key
  on public.inventory_items (organization_id, normalized_sku)
  where normalized_sku is not null;
create index inventory_items_organization_active_idx
  on public.inventory_items (organization_id, is_active, normalized_name);
create index inventory_items_organization_category_idx
  on public.inventory_items (organization_id, category_id);
create index inventory_items_organization_brand_idx
  on public.inventory_items (organization_id, brand_id)
  where brand_id is not null;
create index inventory_items_organization_supplier_idx
  on public.inventory_items (organization_id, preferred_supplier_id)
  where preferred_supplier_id is not null;
create index inventory_movements_organization_created_idx
  on public.inventory_movements (organization_id, created_at desc);
create index inventory_movements_item_created_idx
  on public.inventory_movements (inventory_item_id, created_at desc);

create trigger inventory_brands_set_updated_at
before update on public.inventory_brands
for each row execute function public.set_updated_at();
create trigger suppliers_set_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();
create trigger inventory_items_set_updated_at
before update on public.inventory_items
for each row execute function public.set_updated_at();

create function public.has_inventory_owner_access(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.organizations o on o.id = p.organization_id
    where p.id = auth.uid()
      and p.organization_id = p_organization_id
      and p.role = 'OWNER'
      and p.status = 'ACTIVE'
      and o.status = 'ACTIVE'
      and o.initial_setup_completed
  )
$$;

create function public.assert_inventory_owner()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.current_organization_id();
begin
  if v_organization_id is null
    or not public.has_inventory_owner_access(v_organization_id)
  then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return v_organization_id;
end;
$$;

create function public.protect_inventory_record_identity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.organization_id is distinct from old.organization_id
    or new.created_by is distinct from old.created_by
  then
    raise exception 'Inventory ownership fields are immutable';
  end if;

  return new;
end;
$$;

create trigger inventory_brands_protect_identity
before update on public.inventory_brands
for each row execute function public.protect_inventory_record_identity();
create trigger suppliers_protect_identity
before update on public.suppliers
for each row execute function public.protect_inventory_record_identity();
create trigger inventory_items_protect_identity
before update on public.inventory_items
for each row execute function public.protect_inventory_record_identity();

create function public.prevent_inventory_stock_direct_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.current_stock is distinct from old.current_stock
    and coalesce(current_setting('nodo.inventory_stock_write', true), 'off') <> 'on'
  then
    raise exception 'Inventory stock must be changed through record_inventory_movement';
  end if;

  return new;
end;
$$;

create trigger inventory_items_protect_stock
before update on public.inventory_items
for each row execute function public.prevent_inventory_stock_direct_change();

create function public.prevent_inventory_movement_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'Inventory movements are immutable';
end;
$$;

create trigger inventory_movements_immutable
before update or delete on public.inventory_movements
for each row execute function public.prevent_inventory_movement_mutation();

create function public.record_inventory_movement(
  p_inventory_item_id uuid,
  p_movement_type public.inventory_movement_type,
  p_quantity numeric,
  p_reason text,
  p_unit_cost numeric default null,
  p_reference_type text default null,
  p_reference_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.assert_inventory_owner();
  v_movement_id uuid;
  v_stock_before numeric(14,3);
  v_stock_after numeric(14,3);
  v_quantity_delta numeric(14,3);
  v_reason text := regexp_replace(btrim(coalesce(p_reason, '')), '[[:space:]]+', ' ', 'g');
  v_reference_type text := nullif(
    upper(regexp_replace(btrim(coalesce(p_reference_type, '')), '[[:space:]]+', '_', 'g')),
    ''
  );
begin
  if p_movement_type is null or p_quantity is null or p_quantity = 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  if p_movement_type in ('IN', 'OUT') and p_quantity < 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  v_quantity_delta := case p_movement_type
    when 'IN' then p_quantity
    when 'OUT' then -p_quantity
    when 'ADJUSTMENT' then p_quantity
  end;

  if char_length(v_reason) not between 3 and 500 then
    raise exception 'INVALID_REASON';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'INVALID_UNIT_COST';
  end if;

  if (v_reference_type is null) <> (p_reference_id is null) then
    raise exception 'INVALID_REFERENCE';
  end if;

  if v_reference_type is not null
    and v_reference_type !~ '^[A-Z][A-Z0-9_]{1,49}$'
  then
    raise exception 'INVALID_REFERENCE_TYPE';
  end if;

  select i.current_stock
  into v_stock_before
  from public.inventory_items i
  where i.id = p_inventory_item_id
    and i.organization_id = v_organization_id
    and i.is_active
  for update;

  if not found then
    raise exception 'INVENTORY_ITEM_NOT_FOUND';
  end if;

  v_stock_after := v_stock_before + v_quantity_delta;
  if v_stock_after < 0 then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  perform set_config('nodo.inventory_stock_write', 'on', true);
  update public.inventory_items
  set current_stock = v_stock_after
  where id = p_inventory_item_id
    and organization_id = v_organization_id;
  perform set_config('nodo.inventory_stock_write', 'off', true);

  insert into public.inventory_movements (
    organization_id,
    inventory_item_id,
    movement_type,
    quantity_delta,
    stock_before,
    stock_after,
    unit_cost,
    reason,
    reference_type,
    reference_id,
    actor_user_id
  ) values (
    v_organization_id,
    p_inventory_item_id,
    p_movement_type,
    v_quantity_delta,
    v_stock_before,
    v_stock_after,
    p_unit_cost,
    v_reason,
    v_reference_type,
    p_reference_id,
    auth.uid()
  )
  returning id into v_movement_id;

  return v_movement_id;
end;
$$;

-- Catálogo global reducido y adaptado al servicio técnico; no incluye productos
-- ni stock de la empresa del sistema legado.
insert into public.inventory_categories (name) values
  ('Componentes'),
  ('Repuestos'),
  ('Accesorios'),
  ('Almacenamiento'),
  ('Memorias'),
  ('Energía'),
  ('Herramientas'),
  ('Consumibles')
on conflict (normalized_name) do nothing;

alter table public.inventory_categories enable row level security;
alter table public.inventory_brands enable row level security;
alter table public.suppliers enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_movements enable row level security;

grant select on public.inventory_categories to authenticated;
grant select, insert, update on public.inventory_brands to authenticated;
grant select, insert, update on public.suppliers to authenticated;
grant select, insert, update on public.inventory_items to authenticated;
grant select on public.inventory_movements to authenticated;
grant usage on type public.inventory_movement_type to authenticated;

revoke insert, update, delete on public.inventory_categories from anon, authenticated;
revoke delete on public.inventory_brands, public.suppliers, public.inventory_items from anon, authenticated;
revoke insert, update, delete on public.inventory_movements from anon, authenticated;

create policy inventory_categories_select
on public.inventory_categories
for select
to authenticated
using (is_active or public.current_app_role() = 'SUPERADMIN');

create policy inventory_brands_select
on public.inventory_brands
for select
to authenticated
using (
  public.current_app_role() = 'SUPERADMIN'
  or public.has_inventory_owner_access(organization_id)
);
create policy inventory_brands_insert
on public.inventory_brands
for insert
to authenticated
with check (
  public.has_inventory_owner_access(organization_id)
  and created_by = auth.uid()
);
create policy inventory_brands_update
on public.inventory_brands
for update
to authenticated
using (public.has_inventory_owner_access(organization_id))
with check (public.has_inventory_owner_access(organization_id));

create policy suppliers_select
on public.suppliers
for select
to authenticated
using (
  public.current_app_role() = 'SUPERADMIN'
  or public.has_inventory_owner_access(organization_id)
);
create policy suppliers_insert
on public.suppliers
for insert
to authenticated
with check (
  public.has_inventory_owner_access(organization_id)
  and created_by = auth.uid()
);
create policy suppliers_update
on public.suppliers
for update
to authenticated
using (public.has_inventory_owner_access(organization_id))
with check (public.has_inventory_owner_access(organization_id));

create policy inventory_items_select
on public.inventory_items
for select
to authenticated
using (
  public.current_app_role() = 'SUPERADMIN'
  or public.has_inventory_owner_access(organization_id)
);
create policy inventory_items_insert
on public.inventory_items
for insert
to authenticated
with check (
  public.has_inventory_owner_access(organization_id)
  and created_by = auth.uid()
  and current_stock = 0
);
create policy inventory_items_update
on public.inventory_items
for update
to authenticated
using (public.has_inventory_owner_access(organization_id))
with check (public.has_inventory_owner_access(organization_id));

create policy inventory_movements_select
on public.inventory_movements
for select
to authenticated
using (
  public.current_app_role() = 'SUPERADMIN'
  or public.has_inventory_owner_access(organization_id)
);

revoke all on function public.assert_inventory_owner() from public, anon, authenticated;
revoke all on function public.protect_inventory_record_identity() from public, anon, authenticated;
revoke all on function public.prevent_inventory_stock_direct_change() from public, anon, authenticated;
revoke all on function public.prevent_inventory_movement_mutation() from public, anon, authenticated;
revoke all on function public.record_inventory_movement(
  uuid,
  public.inventory_movement_type,
  numeric,
  text,
  numeric,
  text,
  uuid
) from public, anon;
grant execute on function public.record_inventory_movement(
  uuid,
  public.inventory_movement_type,
  numeric,
  text,
  numeric,
  text,
  uuid
) to authenticated;

comment on table public.inventory_categories is
  'Catálogo global de categorías genéricas de inventario, de solo lectura para usuarios autenticados.';
comment on table public.inventory_brands is
  'Marcas de artículos por organización; se mantiene separado de device_brands para no mezclar repuestos con dispositivos.';
comment on table public.inventory_movements is
  'Historial inmutable y atómico que mantiene sincronizado inventory_items.current_stock.';
comment on function public.record_inventory_movement(
  uuid,
  public.inventory_movement_type,
  numeric,
  text,
  numeric,
  text,
  uuid
) is
  'Registra IN/OUT con cantidad positiva; ADJUSTMENT admite una diferencia con signo. Rechaza saldos negativos.';
