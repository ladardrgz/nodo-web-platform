-- Configuración inicial de organizaciones y logos privados.
alter table public.organizations
  add column if not exists trade_name text,
  add column if not exists logo_path text,
  add column if not exists phone text,
  add column if not exists contact_email text,
  add column if not exists address text,
  add column if not exists locality text,
  add column if not exists province text,
  add column if not exists description text,
  add column if not exists initial_setup_completed boolean;

-- Las organizaciones preexistentes continúan operativas. Las nuevas comienzan pendientes.
update public.organizations
set initial_setup_completed = true
where initial_setup_completed is null;

alter table public.organizations
  alter column initial_setup_completed set default false,
  alter column initial_setup_completed set not null;

create function public.current_organization_setup_completed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(initial_setup_completed, false)
  from public.organizations
  where id = public.current_organization_id()
$$;

alter table public.organizations
  add constraint organizations_setup_fields_length check (
    (trade_name is null or char_length(trade_name) between 2 and 120)
    and (logo_path is null or char_length(logo_path) <= 500)
    and (phone is null or char_length(phone) between 6 and 30)
    and (contact_email is null or char_length(contact_email) <= 254)
    and (address is null or char_length(address) between 3 and 180)
    and (locality is null or char_length(locality) between 2 and 100)
    and (province is null or char_length(province) between 2 and 100)
    and (description is null or char_length(description) between 10 and 600)
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'organization-logos',
  'organization-logos',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy organization_logos_select
on storage.objects for select to authenticated
using (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create policy organization_logos_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create policy organization_logos_update
on storage.objects for update to authenticated
using (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
)
with check (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create policy organization_logos_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'organization-logos'
  and public.current_app_role() = 'OWNER'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

-- La interfaz bloquea las rutas y RLS refuerza el límite sobre los datos operativos existentes.
drop policy if exists customers_select on public.customers;
drop policy if exists customers_insert on public.customers;
drop policy if exists customers_update on public.customers;
drop policy if exists customer_links_select on public.customer_user_links;
drop policy if exists customer_links_insert on public.customer_user_links;
drop policy if exists customer_links_delete on public.customer_user_links;

create policy customers_select on public.customers for select to authenticated using (
  public.current_app_role() = 'SUPERADMIN'
  or (
    organization_id = public.current_organization_id()
    and public.current_organization_setup_completed()
    and (
      public.current_app_role() = 'OWNER'
      or exists (select 1 from public.customer_user_links l where l.customer_id = customers.id and l.auth_user_id = auth.uid())
    )
  )
);
create policy customers_insert on public.customers for insert to authenticated with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_setup_completed()
);
create policy customers_update on public.customers for update to authenticated using (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_setup_completed()
) with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_setup_completed()
);
create policy customer_links_select on public.customer_user_links for select to authenticated using (
  public.current_app_role() = 'SUPERADMIN'
  or auth_user_id = auth.uid()
  or (
    organization_id = public.current_organization_id()
    and public.current_app_role() = 'OWNER'
    and public.current_organization_setup_completed()
  )
);
create policy customer_links_insert on public.customer_user_links for insert to authenticated with check (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_setup_completed()
  and created_by = auth.uid()
);
create policy customer_links_delete on public.customer_user_links for delete to authenticated using (
  organization_id = public.current_organization_id()
  and public.current_app_role() = 'OWNER'
  and public.current_organization_setup_completed()
);

create function public.complete_initial_organization_setup(
  p_name text,
  p_trade_name text,
  p_logo_path text,
  p_phone text,
  p_contact_email text,
  p_address text,
  p_locality text,
  p_province text,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid := public.current_organization_id();
  v_logo_path text := nullif(trim(p_logo_path), '');
begin
  if auth.uid() is null or public.current_app_role() <> 'OWNER' then
    raise exception 'Forbidden';
  end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;
  if char_length(trim(p_name)) not between 2 and 120 then raise exception 'Invalid organization name'; end if;
  if char_length(trim(p_trade_name)) not between 2 and 120 then raise exception 'Invalid trade name'; end if;
  if char_length(trim(p_phone)) not between 6 and 30 then raise exception 'Invalid phone'; end if;
  if trim(p_contact_email) !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email'; end if;
  if char_length(trim(p_address)) not between 3 and 180 then raise exception 'Invalid address'; end if;
  if char_length(trim(p_locality)) not between 2 and 100 then raise exception 'Invalid locality'; end if;
  if char_length(trim(p_province)) not between 2 and 100 then raise exception 'Invalid province'; end if;
  if char_length(trim(p_description)) not between 10 and 600 then raise exception 'Invalid description'; end if;
  if v_logo_path is not null and (
    v_logo_path not like v_organization_id::text || '/%'
    or v_logo_path like '%..%'
  ) then raise exception 'Invalid logo path'; end if;

  update public.organizations
  set
    name = trim(p_name),
    trade_name = trim(p_trade_name),
    logo_path = v_logo_path,
    phone = trim(p_phone),
    contact_email = lower(trim(p_contact_email)),
    address = trim(p_address),
    locality = trim(p_locality),
    province = trim(p_province),
    description = trim(p_description),
    initial_setup_completed = true
  where id = v_organization_id and status = 'ACTIVE';

  if not found then raise exception 'Organization not available'; end if;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization_id, auth.uid(), 'ORGANIZATION_SETUP_COMPLETED', 'ORGANIZATION', v_organization_id, '{}');
end;
$$;

revoke all on function public.complete_initial_organization_setup(text, text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.complete_initial_organization_setup(text, text, text, text, text, text, text, text, text) to authenticated;

comment on column public.organizations.initial_setup_completed is 'Bloquea la operación hasta que el OWNER completa los datos fundamentales.';
comment on column public.organizations.logo_path is 'Ruta privada dentro del bucket organization-logos; nunca almacena el archivo ni una URL firmada.';
