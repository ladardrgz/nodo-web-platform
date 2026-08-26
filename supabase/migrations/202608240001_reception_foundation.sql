-- Recepción técnica: catálogos, dispositivos, inspección inmutable y evidencia privada.
create unique index if not exists customers_organization_phone_unique
  on public.customers (organization_id, phone) where phone is not null and phone <> '';
create unique index if not exists customers_organization_email_unique
  on public.customers (organization_id, lower(contact_email)) where contact_email is not null and contact_email <> '';

create table public.device_types (
  id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 80), category text not null check (char_length(category) between 2 and 80),
  attribute_group text not null check (attribute_group in ('MOBILE','COMPUTER','PRINTER','DISPLAY','NETWORK','GAMING','CAMERA','STORAGE','AUDIO','PERIPHERAL','POWER','COMMERCIAL','OTHER')),
  is_active boolean not null default true, created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create unique index device_types_global_name_unique on public.device_types (lower(name)) where organization_id is null;
create unique index device_types_organization_name_unique on public.device_types (organization_id, lower(name)) where organization_id is not null;

create table public.device_brands (
  id uuid primary key default gen_random_uuid(), organization_id uuid references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 80), categories text[] not null default '{}', is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create unique index device_brands_global_name_unique on public.device_brands (lower(name)) where organization_id is null;
create unique index device_brands_organization_name_unique on public.device_brands (organization_id, lower(name)) where organization_id is not null;

create table public.customer_devices (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid not null, type_id uuid not null references public.device_types(id) on delete restrict, brand_id uuid not null references public.device_brands(id) on delete restrict,
  model text not null check (char_length(trim(model)) between 2 and 120), year smallint check (year between 1950 and 2200), color text check (color is null or char_length(color) <= 80),
  serial_number text check (serial_number is null or char_length(serial_number) <= 120), imei_1 text check (imei_1 is null or imei_1 ~ '^[0-9]{0,20}$'), imei_2 text check (imei_2 is null or imei_2 ~ '^[0-9]{0,20}$'),
  attributes jsonb not null default '{}', memory_modules jsonb not null default '[]', storage_units jsonb not null default '[]', accessories text[] not null default '{}',
  created_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (id, organization_id), foreign key (customer_id, organization_id) references public.customers(id, organization_id) on delete restrict
);
create index customer_devices_organization_created_idx on public.customer_devices (organization_id, created_at desc);
create index customer_devices_customer_idx on public.customer_devices (organization_id, customer_id);
create trigger customer_devices_set_updated_at before update on public.customer_devices for each row execute function public.set_updated_at();

create table public.device_receptions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid not null, device_id uuid not null, reported_problem text not null check (char_length(trim(reported_problem)) between 10 and 2000),
  observations text not null default '' check (char_length(observations) <= 2000), condition_score numeric(6,1) not null check (condition_score >= 0),
  calculated_condition text not null check (calculated_condition in ('Excelente estado','Buen estado','Desgaste normal','Estado regular','Dañado','Muy dañado')),
  intake_snapshot jsonb not null, status text not null default 'CONFIRMED' check (status = 'CONFIRMED'), created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(), unique (id, organization_id),
  foreign key (customer_id, organization_id) references public.customers(id, organization_id) on delete restrict,
  foreign key (device_id, organization_id) references public.customer_devices(id, organization_id) on delete restrict
);
create index device_receptions_organization_created_idx on public.device_receptions (organization_id, created_at desc);
create index device_receptions_device_idx on public.device_receptions (organization_id, device_id);

create table public.reception_inspection_items (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  reception_id uuid not null, item_key text not null check (item_key ~ '^[a-z0-9_]+$'), label text not null check (char_length(label) between 2 and 100),
  condition text not null check (condition in ('NO_DAMAGE','LIGHT_WEAR','SCRATCHED','DENTED','BROKEN','MISSING','NOT_WORKING','NOT_VERIFIABLE','NOT_APPLICABLE')),
  severity numeric(3,1), observation text not null default '' check (char_length(observation) <= 500), is_critical boolean not null default false,
  created_at timestamptz not null default now(), unique (reception_id, item_key),
  foreign key (reception_id, organization_id) references public.device_receptions(id, organization_id) on delete restrict
);
create index reception_inspection_reception_idx on public.reception_inspection_items (organization_id, reception_id);

create table public.reception_photos (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  reception_id uuid not null, storage_path text not null unique check (char_length(storage_path) between 10 and 400),
  description text check (description is null or char_length(description) <= 300), inspection_item_key text check (inspection_item_key is null or inspection_item_key ~ '^[a-z0-9_]+$'),
  uploaded_by uuid not null references auth.users(id) on delete restrict, created_at timestamptz not null default now(),
  foreign key (reception_id, organization_id) references public.device_receptions(id, organization_id) on delete restrict
);
create index reception_photos_reception_idx on public.reception_photos (organization_id, reception_id);

insert into public.device_types (name, category, attribute_group) values
('Celular / Smartphone','Telefonía y dispositivos móviles','MOBILE'),('Teléfono básico','Telefonía y dispositivos móviles','MOBILE'),('Tablet','Telefonía y dispositivos móviles','MOBILE'),('iPad','Telefonía y dispositivos móviles','MOBILE'),('Smartwatch','Telefonía y dispositivos móviles','MOBILE'),('Smartband','Telefonía y dispositivos móviles','MOBILE'),('GPS','Telefonía y dispositivos móviles','MOBILE'),
('Notebook','Computación','COMPUTER'),('Ultrabook','Computación','COMPUTER'),('Netbook','Computación','COMPUTER'),('Chromebook','Computación','COMPUTER'),('MacBook','Computación','COMPUTER'),('PC de escritorio','Computación','COMPUTER'),('PC gamer','Computación','COMPUTER'),('All-in-One','Computación','COMPUTER'),('Mini PC','Computación','COMPUTER'),('Workstation','Computación','COMPUTER'),('Servidor','Computación','COMPUTER'),
('Placa madre','Componentes','OTHER'),('Placa de video','Componentes','OTHER'),('Fuente ATX','Componentes','POWER'),('Fuente de alimentación','Componentes','POWER'),('Disco externo','Componentes','STORAGE'),('SSD externo','Componentes','STORAGE'),('Pendrive','Componentes','STORAGE'),('Lector de tarjetas','Componentes','STORAGE'),
('Monitor','Imagen y visualización','DISPLAY'),('Smart TV','Imagen y visualización','DISPLAY'),('TV LED/LCD','Imagen y visualización','DISPLAY'),('Proyector','Imagen y visualización','DISPLAY'),('Cámara digital','Imagen y visualización','CAMERA'),('Cámara IP','Imagen y visualización','CAMERA'),('Webcam','Imagen y visualización','CAMERA'),
('Impresora láser','Impresión','PRINTER'),('Impresora tinta','Impresión','PRINTER'),('Impresora multifunción','Impresión','PRINTER'),('Impresora térmica','Impresión','PRINTER'),('Impresora de etiquetas','Impresión','PRINTER'),('Scanner','Impresión','PRINTER'),('Fotocopiadora','Impresión','PRINTER'),
('Router','Redes','NETWORK'),('Módem','Redes','NETWORK'),('Access Point','Redes','NETWORK'),('Repetidor Wi-Fi','Redes','NETWORK'),('Switch de red','Redes','NETWORK'),('NAS','Redes','STORAGE'),('DVR','Redes','NETWORK'),('NVR','Redes','NETWORK'),
('Consola de videojuegos','Gaming','GAMING'),('Consola portátil','Gaming','GAMING'),('Joystick / Gamepad','Gaming','PERIPHERAL'),('Teclado','Periféricos','PERIPHERAL'),('Mouse','Periféricos','PERIPHERAL'),('Auriculares','Periféricos','AUDIO'),('Parlante','Periféricos','AUDIO'),('UPS','Energía','POWER'),('Estabilizador','Energía','POWER'),('Equipo de audio','Audio y multimedia','AUDIO'),('Home theater','Audio y multimedia','AUDIO'),('Decodificador / TV Box','Audio y multimedia','AUDIO'),('POS / Terminal de venta','Comercial','COMMERCIAL'),('Lector de código de barras','Comercial','COMMERCIAL')
on conflict do nothing;
insert into public.device_brands (name) select unnest(array['Apple','Samsung','Xiaomi','Motorola','Huawei','Lenovo','HP','Dell','ASUS','Acer','MSI','Gigabyte','Intel','AMD','Epson','Canon','Brother','Lexmark','Sony','LG','TCL','Philips','TP-Link','Logitech','Kingston','Western Digital','Seagate','Crucial','Corsair','HyperX','Razer','Microsoft','Nintendo','PlayStation / Sony','Xbox / Microsoft','Hikvision','Dahua','JBL','Bose','Noblex','RCA']) on conflict do nothing;

create or replace function public.assert_reception_owner() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_org uuid;
begin
 select p.organization_id into v_org from public.profiles p join public.organizations o on o.id=p.organization_id where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and o.status='ACTIVE' and o.initial_setup_completed;
 if v_org is null then raise exception 'FORBIDDEN'; end if; return v_org;
end; $$;

create or replace function public.create_reception_customer(p_first_name text,p_last_name text,p_phone text,p_contact_email text default null)
returns table(id uuid,first_name text,last_name text,phone text,contact_email text) language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid; v_first text:=regexp_replace(trim(p_first_name),'\s+',' ','g'); v_last text:=regexp_replace(trim(p_last_name),'\s+',' ','g'); v_email text:=lower(nullif(trim(p_contact_email),''));
begin
 if char_length(v_first)<2 or v_first !~ '^[[:alpha:]ÁÉÍÓÚáéíóúÑñÜü''’.-]+([ ][[:alpha:]ÁÉÍÓÚáéíóúÑñÜü''’.-]+)*$' then raise exception 'INVALID_FIRST_NAME'; end if;
 if char_length(v_last)<2 or v_last !~ '^[[:alpha:]ÁÉÍÓÚáéíóúÑñÜü''’.-]+([ ][[:alpha:]ÁÉÍÓÚáéíóúÑñÜü''’.-]+)*$' then raise exception 'INVALID_LAST_NAME'; end if;
 if p_phone !~ '^[0-9]{10}$' then raise exception 'INVALID_PHONE'; end if;
 if exists(select 1 from public.customers c where c.organization_id=v_org and c.phone=p_phone) then raise exception 'CUSTOMER_PHONE_EXISTS'; end if;
 if v_email is not null and (v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$') then raise exception 'INVALID_EMAIL'; end if;
 if v_email is not null and exists(select 1 from public.customers c where c.organization_id=v_org and lower(c.contact_email)=v_email) then raise exception 'CUSTOMER_EMAIL_EXISTS'; end if;
 insert into public.customers(organization_id,first_name,last_name,phone,contact_email) values(v_org,v_first,v_last,p_phone,v_email) returning customers.id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'CUSTOMER_CREATED','CUSTOMER',v_id,'{}');
 return query select c.id,c.first_name,c.last_name,c.phone,c.contact_email from public.customers c where c.id=v_id;
exception when unique_violation then if v_email is not null and exists(select 1 from public.customers c where c.organization_id=v_org and lower(c.contact_email)=v_email) then raise exception 'CUSTOMER_EMAIL_EXISTS'; else raise exception 'CUSTOMER_PHONE_EXISTS'; end if; end; $$;

create or replace function public.create_custom_device_type(p_name text) returns setof public.device_types language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_TYPE'; end if;
 if exists(select 1 from public.device_types where (organization_id is null or organization_id=v_org) and lower(name)=lower(v_name)) then raise exception 'DEVICE_TYPE_EXISTS'; end if;
 insert into public.device_types(organization_id,name,category,attribute_group,created_by) values(v_org,v_name,'Personalizados','OTHER',auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_TYPE_CREATED','DEVICE_TYPE',v_id,'{}'); return query select * from public.device_types where id=v_id; end; $$;
create or replace function public.create_custom_device_brand(p_name text) returns setof public.device_brands language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_BRAND'; end if;
 if exists(select 1 from public.device_brands where (organization_id is null or organization_id=v_org) and lower(name)=lower(v_name)) then raise exception 'DEVICE_BRAND_EXISTS'; end if;
 insert into public.device_brands(organization_id,name,created_by) values(v_org,v_name,auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_BRAND_CREATED','DEVICE_BRAND',v_id,'{}'); return query select * from public.device_brands where id=v_id; end; $$;

create or replace function public.create_customer_device(p_customer_id uuid,p_type_id uuid,p_brand_id uuid,p_model text,p_year text,p_color text,p_serial_number text,p_imei_1 text,p_imei_2 text,p_attributes jsonb,p_memories jsonb,p_storage_units jsonb,p_accessories text[])
returns uuid language plpgsql security definer set search_path='' as $$ declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin
 perform 1 from public.customers where id=p_customer_id and organization_id=v_org; if not found then raise exception 'INVALID_CUSTOMER'; end if;
 perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
 perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
 insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
 values(v_org,p_customer_id,p_type_id,p_brand_id,regexp_replace(trim(p_model),'\s+',' ','g'),nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),nullif(trim(p_imei_1),''),nullif(trim(p_imei_2),''),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_id,jsonb_build_object('customer_id',p_customer_id)); return v_id; end; $$;

create or replace function public.confirm_device_reception(p_customer_id uuid,p_device_id uuid,p_reported_problem text,p_observations text,p_inspection jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid; v_score numeric:=0; v_condition text; v_item jsonb; v_weight numeric; v_critical boolean;
begin
 perform 1 from public.customer_devices where id=p_device_id and customer_id=p_customer_id and organization_id=v_org; if not found then raise exception 'INVALID_DEVICE'; end if;
 if char_length(trim(p_reported_problem)) not between 10 and 2000 or jsonb_typeof(p_inspection)<>'array' or jsonb_array_length(p_inspection)=0 then raise exception 'INVALID_RECEPTION'; end if;
 for v_item in select value from jsonb_array_elements(p_inspection) loop
  if (v_item->>'condition') not in ('NO_DAMAGE','LIGHT_WEAR','SCRATCHED','DENTED','BROKEN','MISSING','NOT_WORKING','NOT_VERIFIABLE','NOT_APPLICABLE') then raise exception 'INVALID_INSPECTION'; end if;
  v_weight:=case v_item->>'condition' when 'NO_DAMAGE' then 0 when 'LIGHT_WEAR' then .5 when 'SCRATCHED' then 1 when 'DENTED' then 2 when 'BROKEN' then 3 when 'MISSING' then 3 when 'NOT_WORKING' then 3 else null end; v_score:=v_score+coalesce(v_weight,0);
 end loop;
 v_condition:=case when v_score=0 then 'Excelente estado' when v_score<=2 then 'Buen estado' when v_score<=4 then 'Desgaste normal' when v_score<=7 then 'Estado regular' when v_score<=12 then 'Dañado' else 'Muy dañado' end;
 insert into public.device_receptions(organization_id,customer_id,device_id,reported_problem,observations,condition_score,calculated_condition,intake_snapshot,created_by)
 values(v_org,p_customer_id,p_device_id,regexp_replace(trim(p_reported_problem),'\s+',' ','g'),regexp_replace(trim(coalesce(p_observations,'')),'\s+',' ','g'),v_score,v_condition,jsonb_build_object('reported_problem',p_reported_problem,'observations',p_observations,'inspection',p_inspection,'calculated_condition',v_condition,'condition_score',v_score),auth.uid()) returning id into v_id;
 for v_item in select value from jsonb_array_elements(p_inspection) loop
  v_weight:=case v_item->>'condition' when 'NO_DAMAGE' then 0 when 'LIGHT_WEAR' then .5 when 'SCRATCHED' then 1 when 'DENTED' then 2 when 'BROKEN' then 3 when 'MISSING' then 3 when 'NOT_WORKING' then 3 else null end;
  v_critical:=(v_item->>'key') in ('screen','hinges','charge_port','liquid','battery','seals','screws','prior_opening') and (v_item->>'condition') in ('DENTED','BROKEN','MISSING','NOT_WORKING');
  insert into public.reception_inspection_items(organization_id,reception_id,item_key,label,condition,severity,observation,is_critical) values(v_org,v_id,v_item->>'key',left(v_item->>'label',100),v_item->>'condition',v_weight,left(coalesce(v_item->>'observation',''),500),v_critical);
 end loop;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'RECEPTION_CONFIRMED','DEVICE_RECEPTION',v_id,jsonb_build_object('device_id',p_device_id,'condition',v_condition)); return v_id; end; $$;

create or replace function public.register_reception_photo(p_reception_id uuid,p_storage_path text,p_description text,p_inspection_key text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin perform 1 from public.device_receptions where id=p_reception_id and organization_id=v_org; if not found or p_storage_path not like v_org::text||'/'||p_reception_id::text||'/%' then raise exception 'INVALID_PHOTO'; end if;
 insert into public.reception_photos(organization_id,reception_id,storage_path,description,inspection_item_key,uploaded_by) values(v_org,p_reception_id,p_storage_path,nullif(trim(p_description),''),nullif(p_inspection_key,''),auth.uid()) returning id into v_id; return v_id; end; $$;

create or replace function public.prevent_confirmed_reception_mutation() returns trigger language plpgsql set search_path='' as $$ begin raise exception 'CONFIRMED_RECEPTION_IMMUTABLE'; end; $$;
create trigger device_receptions_immutable before update or delete on public.device_receptions for each row execute function public.prevent_confirmed_reception_mutation();
create trigger reception_items_immutable before update or delete on public.reception_inspection_items for each row execute function public.prevent_confirmed_reception_mutation();

alter table public.device_types enable row level security; alter table public.device_brands enable row level security; alter table public.customer_devices enable row level security; alter table public.device_receptions enable row level security; alter table public.reception_inspection_items enable row level security; alter table public.reception_photos enable row level security;
create policy device_types_select on public.device_types for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy device_brands_select on public.device_brands for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
create policy customer_devices_select on public.customer_devices for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
create policy device_receptions_select on public.device_receptions for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
create policy reception_items_select on public.reception_inspection_items for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
create policy reception_photos_select on public.reception_photos for select to authenticated using (organization_id=public.current_organization_id() and public.current_app_role()='OWNER');
grant select on public.device_types,public.device_brands,public.customer_devices,public.device_receptions,public.reception_inspection_items,public.reception_photos to authenticated;
revoke all on function public.assert_reception_owner() from public,anon; revoke all on function public.create_reception_customer(text,text,text,text) from public,anon; revoke all on function public.create_custom_device_type(text) from public,anon; revoke all on function public.create_custom_device_brand(text) from public,anon; revoke all on function public.create_customer_device(uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) from public,anon; revoke all on function public.confirm_device_reception(uuid,uuid,text,text,jsonb) from public,anon; revoke all on function public.register_reception_photo(uuid,text,text,text) from public,anon;
grant execute on function public.create_reception_customer(text,text,text,text),public.create_custom_device_type(text),public.create_custom_device_brand(text),public.create_customer_device(uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]),public.confirm_device_reception(uuid,uuid,text,text,jsonb),public.register_reception_photo(uuid,text,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('reception-photos','reception-photos',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy reception_photos_storage_select on storage.objects for select to authenticated using(bucket_id='reception-photos' and (storage.foldername(name))[1]=public.current_organization_id()::text and public.current_app_role()='OWNER');
create policy reception_photos_storage_insert on storage.objects for insert to authenticated with check(bucket_id='reception-photos' and (storage.foldername(name))[1]=public.current_organization_id()::text and public.current_app_role()='OWNER');
create policy reception_photos_storage_delete on storage.objects for delete to authenticated using(bucket_id='reception-photos' and (storage.foldername(name))[1]=public.current_organization_id()::text and public.current_app_role()='OWNER');

comment on table public.device_receptions is 'Snapshot inmutable del estado observado al recibir el equipo; hallazgos posteriores deben registrarse por separado.';
comment on table public.reception_photos is 'Metadatos de evidencia privada; el archivo reside en Supabase Storage.';
