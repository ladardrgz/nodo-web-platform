-- Paso 3 persistente del onboarding OWNER: ubicación estructurada.
create table public.countries (
  id text primary key check (id ~ '^[A-Z]{2}$'),
  name text not null check (char_length(name) between 2 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.provinces (
  id text primary key check (char_length(id) between 1 and 20),
  country_id text not null references public.countries(id) on delete restrict,
  name text not null check (char_length(name) between 2 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, country_id)
);

create table public.localities (
  id text primary key check (char_length(id) between 1 and 40),
  province_id text not null references public.provinces(id) on delete restrict,
  name text not null check (char_length(name) between 2 and 140),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, province_id)
);

create table public.neighborhoods (
  id text primary key check (char_length(id) between 1 and 80),
  locality_id text not null references public.localities(id) on delete restrict,
  name text not null check (char_length(name) between 2 and 140),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, locality_id)
);

create table public.organization_addresses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete restrict,
  country_id text not null,
  province_id text not null,
  locality_id text not null,
  neighborhood_id text,
  street text not null check (char_length(street) between 2 and 120 and street !~ '[<>]' and street !~ '[[:cntrl:]]'),
  street_number integer check (street_number between 1 and 999999),
  without_number boolean not null default false,
  floor text check (floor is null or (char_length(floor) <= 10 and floor !~ '[<>]' and floor !~ '[[:cntrl:]]')),
  apartment text check (apartment is null or (char_length(apartment) <= 10 and apartment !~ '[<>]' and apartment !~ '[[:cntrl:]]')),
  postal_code text check (postal_code is null or char_length(postal_code) between 4 and 10),
  reference text check (reference is null or (char_length(reference) <= 200 and reference !~ '[<>]' and reference !~ '[[:cntrl:]]')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_addresses_number_check check (
    (without_number and street_number is null)
    or (not without_number and street_number is not null)
  ),
  foreign key (province_id, country_id) references public.provinces(id, country_id) on delete restrict,
  foreign key (locality_id, province_id) references public.localities(id, province_id) on delete restrict,
  foreign key (neighborhood_id, locality_id) references public.neighborhoods(id, locality_id) on delete restrict
);

create index provinces_country_idx on public.provinces (country_id, name);
create index localities_province_idx on public.localities (province_id, name);
create index neighborhoods_locality_idx on public.neighborhoods (locality_id, name);

create trigger organization_addresses_set_updated_at
before update on public.organization_addresses
for each row execute function public.set_updated_at();

-- Catálogo oficial GeoRef Argentina. No se cargan barrios sin un dataset fiable.
insert into public.countries (id, name) values ('AR', 'Argentina');

insert into public.provinces (id, country_id, name) values
  ('02', 'AR', 'Ciudad Autónoma de Buenos Aires'),
  ('06', 'AR', 'Buenos Aires'),
  ('10', 'AR', 'Catamarca'),
  ('14', 'AR', 'Córdoba'),
  ('18', 'AR', 'Corrientes'),
  ('22', 'AR', 'Chaco'),
  ('26', 'AR', 'Chubut'),
  ('30', 'AR', 'Entre Ríos'),
  ('34', 'AR', 'Formosa'),
  ('38', 'AR', 'Jujuy'),
  ('42', 'AR', 'La Pampa'),
  ('46', 'AR', 'La Rioja'),
  ('50', 'AR', 'Mendoza'),
  ('54', 'AR', 'Misiones'),
  ('58', 'AR', 'Neuquén'),
  ('62', 'AR', 'Río Negro'),
  ('66', 'AR', 'Salta'),
  ('70', 'AR', 'San Juan'),
  ('74', 'AR', 'San Luis'),
  ('78', 'AR', 'Santa Cruz'),
  ('82', 'AR', 'Santa Fe'),
  ('86', 'AR', 'Santiago del Estero'),
  ('90', 'AR', 'Tucumán'),
  ('94', 'AR', 'Tierra del Fuego, Antártida e Islas del Atlántico Sur');

-- Única localidad incorporada en este incremento, con ID oficial GeoRef.
insert into public.localities (id, province_id, name)
values ('34014020', '34', 'Formosa');

alter table public.countries enable row level security;
alter table public.provinces enable row level security;
alter table public.localities enable row level security;
alter table public.neighborhoods enable row level security;
alter table public.organization_addresses enable row level security;

grant select on public.countries, public.provinces, public.localities, public.neighborhoods to authenticated;
grant select, insert, update on public.organization_addresses to authenticated;

create policy countries_read on public.countries for select to authenticated using (is_active);
create policy provinces_read on public.provinces for select to authenticated using (is_active);
create policy localities_read on public.localities for select to authenticated using (is_active);
create policy neighborhoods_read on public.neighborhoods for select to authenticated using (is_active);

create policy organization_addresses_select on public.organization_addresses for select to authenticated using (
  public.current_app_role() = 'SUPERADMIN'
  or (organization_id = public.current_organization_id() and public.current_app_role() = 'OWNER')
);
create policy organization_addresses_insert on public.organization_addresses for insert to authenticated with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and exists (select 1 from public.profiles where id = auth.uid() and status = 'ACTIVE')
  and exists (select 1 from public.organizations o where o.id = organization_addresses.organization_id and o.status = 'ACTIVE')
);
create policy organization_addresses_update on public.organization_addresses for update to authenticated using (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and exists (select 1 from public.profiles where id = auth.uid() and status = 'ACTIVE')
  and exists (select 1 from public.organizations o where o.id = organization_addresses.organization_id and o.status = 'ACTIVE')
) with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and exists (select 1 from public.profiles where id = auth.uid() and status = 'ACTIVE')
  and exists (select 1 from public.organizations o where o.id = organization_addresses.organization_id and o.status = 'ACTIVE')
);

create function public.save_initial_organization_step_three(
  p_country_id text,
  p_province_id text,
  p_locality_id text,
  p_neighborhood_id text,
  p_street text,
  p_street_number integer,
  p_without_number boolean,
  p_floor text,
  p_apartment text,
  p_postal_code text,
  p_reference text
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.current_organization_id();
  v_neighborhood_id text := nullif(trim(p_neighborhood_id), '');
  v_street text := regexp_replace(trim(p_street), '[[:space:]]+', ' ', 'g');
  v_floor text := nullif(regexp_replace(trim(p_floor), '[[:space:]]+', ' ', 'g'), '');
  v_apartment text := nullif(regexp_replace(trim(p_apartment), '[[:space:]]+', ' ', 'g'), '');
  v_postal_code text := nullif(upper(trim(p_postal_code)), '');
  v_reference text := nullif(regexp_replace(trim(p_reference), '[[:space:]]+', ' ', 'g'), '');
  v_next_step smallint;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or not exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'OWNER' and status = 'ACTIVE'
        and organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;
  if not exists (select 1 from public.countries where id = p_country_id and is_active) then raise exception 'Invalid country'; end if;
  if not exists (select 1 from public.provinces where id = p_province_id and country_id = p_country_id and is_active) then raise exception 'Invalid province hierarchy'; end if;
  if not exists (select 1 from public.localities where id = p_locality_id and province_id = p_province_id and is_active) then raise exception 'Invalid locality hierarchy'; end if;
  if exists (select 1 from public.neighborhoods where locality_id = p_locality_id and is_active)
    and v_neighborhood_id is null then raise exception 'Neighborhood required'; end if;
  if v_neighborhood_id is not null and not exists (
    select 1 from public.neighborhoods where id = v_neighborhood_id and locality_id = p_locality_id and is_active
  ) then raise exception 'Invalid neighborhood hierarchy'; end if;
  if char_length(v_street) not between 2 and 120 or v_street ~ '[<>]' or v_street ~ '[[:cntrl:]]' then raise exception 'Invalid street'; end if;
  if (p_without_number and p_street_number is not null)
    or (not p_without_number and (p_street_number is null or p_street_number not between 1 and 999999)) then
    raise exception 'Invalid street number';
  end if;
  if v_floor is not null and char_length(v_floor) > 10 then raise exception 'Invalid floor'; end if;
  if v_apartment is not null and char_length(v_apartment) > 10 then raise exception 'Invalid apartment'; end if;
  if v_postal_code is not null and v_postal_code !~ '^[A-Z0-9-]{4,10}$' then raise exception 'Invalid postal code'; end if;
  if v_reference is not null and (char_length(v_reference) > 200 or v_reference ~ '[<>]' or v_reference ~ '[[:cntrl:]]') then raise exception 'Invalid reference'; end if;

  if not exists (
    select 1 from public.organizations
    where id = v_organization_id and status = 'ACTIVE'
      and initial_setup_completed = false and initial_setup_step >= 3
  ) then raise exception 'Organization unavailable'; end if;

  insert into public.organization_addresses (
    organization_id, country_id, province_id, locality_id, neighborhood_id,
    street, street_number, without_number, floor, apartment, postal_code, reference
  ) values (
    v_organization_id, p_country_id, p_province_id, p_locality_id, v_neighborhood_id,
    v_street, p_street_number, p_without_number, v_floor, v_apartment, v_postal_code, v_reference
  )
  on conflict (organization_id) do update set
    country_id = excluded.country_id,
    province_id = excluded.province_id,
    locality_id = excluded.locality_id,
    neighborhood_id = excluded.neighborhood_id,
    street = excluded.street,
    street_number = excluded.street_number,
    without_number = excluded.without_number,
    floor = excluded.floor,
    apartment = excluded.apartment,
    postal_code = excluded.postal_code,
    reference = excluded.reference;

  update public.organizations
  set initial_setup_step = greatest(initial_setup_step, 4)
  where id = v_organization_id
  returning initial_setup_step into v_next_step;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization_id, auth.uid(), 'ORGANIZATION_SETUP_STEP_THREE_SAVED', 'ORGANIZATION', v_organization_id, jsonb_build_object('step', 3));

  return v_next_step;
end;
$$;

revoke all on function public.save_initial_organization_step_three(text, text, text, text, text, integer, boolean, text, text, text, text) from public, anon;
grant execute on function public.save_initial_organization_step_three(text, text, text, text, text, integer, boolean, text, text, text, text) to authenticated;

comment on table public.organization_addresses is 'Domicilio principal estructurado; una fila por organización en el MVP.';
comment on table public.neighborhoods is 'Catálogo vacío hasta incorporar un dataset de barrios confiable.';
