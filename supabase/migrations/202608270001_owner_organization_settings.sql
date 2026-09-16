-- Configuración permanente del negocio: teléfono internacional y domicilio estructurado.
alter table public.organizations
  add column if not exists phone_country_code text,
  add column if not exists phone_calling_code text,
  add column if not exists phone_national_number text;

alter table public.organizations drop constraint if exists organizations_phone_components_check;
alter table public.organizations add constraint organizations_phone_components_check check (
  (phone_country_code is null and phone_calling_code is null and phone_national_number is null)
  or (
    phone_country_code ~ '^[A-Z]{2}$'
    and phone_calling_code ~ '^\+[1-9][0-9]{0,3}$'
    and phone_national_number ~ '^[0-9]{4,15}$'
    and phone = phone_calling_code || phone_national_number
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('organization-logos', 'organization-logos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp', 'image/avif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.update_owner_organization_settings(
  p_name text,
  p_logo_path text,
  p_phone text,
  p_phone_country_code text,
  p_phone_calling_code text,
  p_phone_national_number text,
  p_contact_email text,
  p_country_id text,
  p_province_id text,
  p_locality_id text,
  p_neighborhood_id text,
  p_street text,
  p_street_number integer,
  p_without_number boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.current_organization_id();
  v_name text := regexp_replace(trim(p_name), '[[:space:]]+', ' ', 'g');
  v_logo_path text := nullif(trim(p_logo_path), '');
  v_phone text := trim(p_phone);
  v_phone_country_code text := upper(trim(p_phone_country_code));
  v_phone_calling_code text := trim(p_phone_calling_code);
  v_phone_national_number text := trim(p_phone_national_number);
  v_contact_email text := lower(trim(p_contact_email));
  v_neighborhood_id text := nullif(trim(p_neighborhood_id), '');
  v_street text := regexp_replace(trim(p_street), '[[:space:]]+', ' ', 'g');
  v_locality_name text;
  v_province_name text;
  v_old_logo_path text;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or v_organization_id is null
    or not exists (
      select 1 from public.profiles
      where id = auth.uid()
        and role = 'OWNER'
        and status = 'ACTIVE'
        and organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;

  select logo_path into v_old_logo_path
  from public.organizations
  where id = v_organization_id and status = 'ACTIVE' and initial_setup_completed
  for update;
  if not found then raise exception 'Organization not available'; end if;

  if char_length(v_name) not between 2 and 120 or v_name ~ '[<>]' or v_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid organization name';
  end if;
  if v_phone_country_code !~ '^[A-Z]{2}$'
    or v_phone_calling_code !~ '^\+[1-9][0-9]{0,3}$'
    or v_phone_national_number !~ '^[0-9]{4,15}$'
    or v_phone <> v_phone_calling_code || v_phone_national_number
    or (v_phone_country_code = 'AR' and char_length(v_phone_national_number) <> 10) then
    raise exception 'Invalid phone';
  end if;
  if v_contact_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or char_length(v_contact_email) > 254 then
    raise exception 'Invalid email';
  end if;
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
  if v_logo_path is not null and (
    char_length(v_logo_path) > 500
    or v_logo_path not like v_organization_id::text || '/%'
    or v_logo_path like '%..%'
  ) then raise exception 'Invalid logo path'; end if;

  select name into v_locality_name from public.localities where id = p_locality_id;
  select name into v_province_name from public.provinces where id = p_province_id;

  update public.organizations
  set
    name = v_name,
    trade_name = v_name,
    logo_path = v_logo_path,
    phone = v_phone,
    phone_country_code = v_phone_country_code,
    phone_calling_code = v_phone_calling_code,
    phone_national_number = v_phone_national_number,
    contact_email = v_contact_email,
    address = v_street || ' ' || case when p_without_number then 'S/N' else p_street_number::text end,
    locality = v_locality_name,
    province = v_province_name
  where id = v_organization_id;

  insert into public.organization_addresses (
    organization_id, country_id, province_id, locality_id, neighborhood_id,
    street, street_number, without_number
  ) values (
    v_organization_id, p_country_id, p_province_id, p_locality_id, v_neighborhood_id,
    v_street, p_street_number, p_without_number
  )
  on conflict (organization_id) do update set
    country_id = excluded.country_id,
    province_id = excluded.province_id,
    locality_id = excluded.locality_id,
    neighborhood_id = excluded.neighborhood_id,
    street = excluded.street,
    street_number = excluded.street_number,
    without_number = excluded.without_number;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_organization_id,
    auth.uid(),
    'ORGANIZATION_UPDATED',
    'ORGANIZATION',
    v_organization_id,
    jsonb_build_object(
      'sections', jsonb_build_array('identity', 'contact', 'location'),
      'logo_updated', v_logo_path is distinct from v_old_logo_path
    )
  );
end;
$$;

revoke all on function public.update_owner_organization_settings(text, text, text, text, text, text, text, text, text, text, text, text, integer, boolean) from public, anon;
grant execute on function public.update_owner_organization_settings(text, text, text, text, text, text, text, text, text, text, text, text, integer, boolean) to authenticated;

comment on column public.organizations.phone is 'Teléfono E.164 normalizado de contacto del negocio.';
comment on column public.organizations.phone_country_code is 'Código ISO 3166-1 alpha-2 derivado y validado en servidor.';
comment on column public.organizations.phone_calling_code is 'Prefijo telefónico internacional con signo +.';
comment on column public.organizations.phone_national_number is 'Número nacional normalizado, sin prefijo internacional.';
comment on function public.update_owner_organization_settings(text, text, text, text, text, text, text, text, text, text, text, text, integer, boolean) is
  'Actualiza de forma transaccional los datos no administrativos y el domicilio de la organización OWNER autenticada.';
