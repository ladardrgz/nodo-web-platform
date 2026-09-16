-- Consolidación final de tipos globales sin eliminar datos históricos.
-- Las filas existentes conservan sus FK; los duplicados dejan de ofrecerse.

update public.device_types
set name = 'PC', is_active = true
where organization_id is null
  and public.normalize_catalog_name(name) = public.normalize_catalog_name('PC de escritorio')
  and not exists (
    select 1 from public.device_types canonical
    where canonical.organization_id is null
      and canonical.id <> device_types.id
      and public.normalize_catalog_name(canonical.name) = public.normalize_catalog_name('PC')
  );

update public.device_types legacy
set is_active = false
where legacy.organization_id is null
  and public.normalize_catalog_name(legacy.name) = public.normalize_catalog_name('PC de escritorio')
  and exists (
    select 1 from public.device_types canonical
    where canonical.organization_id is null
      and canonical.id <> legacy.id
      and public.normalize_catalog_name(canonical.name) = public.normalize_catalog_name('PC')
  );

update public.device_types
set is_active = false
where organization_id is null
  and public.normalize_catalog_name(name) in (
    public.normalize_catalog_name('Laptop'),
    public.normalize_catalog_name('Notebook / Laptop'),
    public.normalize_catalog_name('Notebook-Laptop')
  );

update public.device_types
set is_active = true
where organization_id is null
  and public.normalize_catalog_name(name) = public.normalize_catalog_name('Notebook');

comment on table public.device_types is
  'Tipos globales y por organización. Los duplicados se desactivan para nuevas altas; nunca se borran si pueden estar referenciados históricamente.';
