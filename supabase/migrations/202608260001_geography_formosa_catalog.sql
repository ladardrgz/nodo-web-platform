-- Completa el catálogo geográfico existente con el dataset de FormoStock.
-- Los nombres visibles se conservan; normalized_name se usa solo para búsqueda y unicidad.
create function public.normalize_catalog_name(p_value text)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select translate(
    lower(regexp_replace(btrim(p_value), '[[:space:]]+', ' ', 'g')),
    'áéíóúüñ',
    'aeiouun'
  )
$$;

alter table public.countries
  add column normalized_name text generated always as (public.normalize_catalog_name(name)) stored;
alter table public.provinces
  add column normalized_name text generated always as (public.normalize_catalog_name(name)) stored;
alter table public.localities
  add column normalized_name text generated always as (public.normalize_catalog_name(name)) stored;
alter table public.neighborhoods
  add column normalized_name text generated always as (public.normalize_catalog_name(name)) stored;

create unique index countries_normalized_name_key
  on public.countries (normalized_name);
create unique index provinces_country_normalized_name_key
  on public.provinces (country_id, normalized_name);
create unique index localities_province_normalized_name_key
  on public.localities (province_id, normalized_name);
create unique index neighborhoods_locality_normalized_name_key
  on public.neighborhoods (locality_id, normalized_name);

revoke insert, update, delete
on public.countries, public.provinces, public.localities, public.neighborhoods
from anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from public.countries
    where id = 'AR'
      and normalized_name = public.normalize_catalog_name('Argentina')
  ) then
    raise exception 'Geography prerequisite conflict: country AR/Argentina is missing or inconsistent';
  end if;

  if not exists (
    select 1
    from public.provinces
    where id = '34'
      and country_id = 'AR'
      and normalized_name = public.normalize_catalog_name('Formosa')
  ) then
    raise exception 'Geography prerequisite conflict: province 34/Formosa is missing or inconsistent';
  end if;

  if not exists (
    select 1
    from public.localities
    where id = '34014020'
      and province_id = '34'
      and normalized_name = public.normalize_catalog_name('Formosa')
  ) then
    raise exception 'Geography prerequisite conflict: locality 34014020/Formosa is missing or inconsistent';
  end if;
end;
$$;

-- Formosa capital ya existe con su ID GeoRef. Los IDs fs-* son identificadores
-- estables de Nodo para los otros nombres cuya fuente es el SQL legado.
insert into public.localities (id, province_id, name) values
  ('fs-34-pirane', '34', 'Pirané'),
  ('fs-34-pozo-del-tigre', '34', 'Pozo del Tigre'),
  ('fs-34-laishi', '34', 'Laishí'),
  ('fs-34-san-martin-ii', '34', 'San Martín II'),
  ('fs-34-villa-dos-trece', '34', 'Villa Dos Trece'),
  ('fs-34-villafane', '34', 'Villafañe'),
  ('fs-34-ramon-lista', '34', 'Ramón Lista'),
  ('fs-34-rio-muerto', '34', 'Río Muerto'),
  ('fs-34-pilcomayo', '34', 'Pilcomayo'),
  ('fs-34-gral-belgrano', '34', 'Gral Belgrano'),
  ('fs-34-pilagas', '34', 'Pilagás'),
  ('fs-34-matacos', '34', 'Matacos'),
  ('fs-34-bermejo', '34', 'Bermejo'),
  ('fs-34-las-lomitas', '34', 'Las Lomitas'),
  ('fs-34-guemes', '34', 'Guemes')
on conflict do nothing;

do $$
declare
  v_names constant text[] := array[
    '1 de Mayo',
    '2 de Abril',
    '6 de Enero',
    '8 de Marzo',
    '8 de Octubre',
    '12 de Octubre',
    '16 de Julio',
    '25 de Mayo',
    'Acceso a Curuzú La Novia',
    'Acceso Tres Marías',
    'Benedetto Fachini',
    'Bernardino Rivadavia',
    'Caracolito',
    'Carlos Menem Jr.',
    'COVIFOL',
    'Don Bosco',
    'Loteo Don Juan',
    'El Palmar',
    'El Palomar',
    'El Paraíso',
    'El Porvenir',
    'El Pucú',
    'El Quebrachito',
    'El Quebranto',
    'El Resguardo',
    'Emilio Tomás',
    'Eva Perón',
    'Fleming',
    'Fontana',
    'Frente al Aeropuerto',
    'Guadalupe',
    'Ibyrá Pitá',
    'Illia I',
    'Itatí I',
    'Itatí II',
    'Juan Manuel de Rosas',
    'Juan Pablo II',
    'La Alborada',
    'La Estrella',
    'La Floresta',
    'La Palomita',
    'Laguna Siam',
    'La Nueva Formosa',
    'Las Delicias',
    'Las Orquídeas',
    'Libertad',
    'Lisbel Rivira',
    'Lote 4',
    'Lote 67',
    'Lote 110',
    'Lote 111',
    'Lote Rural 3 Bis',
    'Lote Rural 148',
    'Lote Rural 222',
    'Los Inmigrantes',
    'Los Naranjos',
    'Los Pinos',
    'Luján',
    'Malvinas',
    'Mariano Moreno',
    'Medalla Milagrosa',
    'Militar',
    'Namqom',
    'Nueva Pompeya',
    'Obrero',
    'Parque Urbano',
    'Parque Urbano I',
    'Parque Urbano II',
    'PROCREAR',
    'Roberto Sotelo',
    'Sagrado Corazón',
    'Sagrado Corazón de María',
    'San Agustín',
    'San Andrés',
    'San Andrés II',
    'San Antonio',
    'San Antonio I',
    'San Antonio II',
    'San Carlos',
    'San Cayetano',
    'San Fernando',
    'San Francisco',
    'San Isidro Labrador',
    'San Jorge',
    'San José',
    'San José Obrero',
    'San Juan',
    'San Juan I',
    'San Juan II',
    'San Juan Bautista',
    'San Lorenzo',
    'San Martín',
    'San Martín Norte',
    'San Martín Sur',
    'San Miguel',
    'San Pedro',
    'San Pío X',
    'San Roque',
    'Santa Isabel',
    'Santa Rosa',
    'Simón Bolívar',
    'Solano Lima',
    'Stella Maris',
    'Urbanización Maradona',
    'Venezuela',
    'Vial',
    'Villa 49',
    'Villa del Carmen',
    'Villa del Carmen 1',
    'Villa del Carmen 2',
    'Villa del Rosario',
    'Villa Hermosa',
    'Villa Jardín',
    'Villa Lourdes',
    'Virgen de Lourdes',
    'Virgen de Pompeya',
    'Virgen del Pilar',
    'Virgen del Rosario'
  ];
  v_expected_count integer := cardinality(v_names);
  v_loaded_count integer;
begin
  insert into public.neighborhoods (id, locality_id, name)
  select
    'fs-34014020-b' || lpad(source.ordinality::text, 3, '0'),
    '34014020',
    source.name
  from unnest(v_names) with ordinality as source(name, ordinality)
  on conflict do nothing;

  select count(*)
  into v_loaded_count
  from unnest(v_names) as expected(name)
  join public.neighborhoods n
    on n.locality_id = '34014020'
   and n.normalized_name = public.normalize_catalog_name(expected.name);

  if v_loaded_count <> v_expected_count then
    raise exception 'Formosa neighborhood seed incomplete: expected %, found %', v_expected_count, v_loaded_count;
  end if;
end;
$$;

do $$
declare
  v_expected_localities constant text[] := array[
    'Formosa', 'Pirané', 'Pozo del Tigre', 'Laishí', 'San Martín II',
    'Villa Dos Trece', 'Villafañe', 'Ramón Lista', 'Río Muerto', 'Pilcomayo',
    'Gral Belgrano', 'Pilagás', 'Matacos', 'Bermejo', 'Las Lomitas', 'Guemes'
  ];
  v_loaded_count integer;
begin
  select count(*)
  into v_loaded_count
  from unnest(v_expected_localities) as expected(name)
  join public.localities l
    on l.province_id = '34'
   and l.normalized_name = public.normalize_catalog_name(expected.name);

  if v_loaded_count <> cardinality(v_expected_localities) then
    raise exception 'Formosa locality seed incomplete: expected %, found %', cardinality(v_expected_localities), v_loaded_count;
  end if;

  if exists (
    select 1
    from public.provinces p
    left join public.countries c on c.id = p.country_id
    where c.id is null
  ) or exists (
    select 1
    from public.localities l
    left join public.provinces p on p.id = l.province_id
    where p.id is null
  ) or exists (
    select 1
    from public.neighborhoods n
    left join public.localities l on l.id = n.locality_id
    where l.id is null
  ) then
    raise exception 'Geography integrity check failed: orphaned catalog rows detected';
  end if;
end;
$$;

comment on function public.normalize_catalog_name(text) is
  'Normaliza espacios, mayúsculas y diacríticos para comparar catálogos sin alterar el nombre visible.';
comment on table public.neighborhoods is
  'Catálogo global de barrios. El conjunto inicial de Formosa capital proviene de bdformostock_schema.sql.';
