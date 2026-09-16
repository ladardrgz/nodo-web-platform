-- Catálogo extensible de modelos: SYSTEM (organization_id null) y ORGANIZATION.
-- No se elimina ni modifica información de dispositivos o recepciones existentes.

create table if not exists public.device_models (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  device_type_id uuid not null references public.device_types(id) on delete restrict,
  brand_id uuid not null references public.device_brands(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 120),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists device_models_system_unique
  on public.device_models (device_type_id, brand_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g')))
  where organization_id is null;
create unique index if not exists device_models_organization_unique
  on public.device_models (organization_id, device_type_id, brand_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g')))
  where organization_id is not null;
create index if not exists device_models_lookup_idx
  on public.device_models (device_type_id, brand_id, organization_id, name) where is_active;

alter table public.customer_devices
  add column if not exists model_id uuid references public.device_models(id) on delete set null;

-- Mantiene los tipos genéricos como punto de entrada; los modelos distinguen la generación.
update public.device_types set is_active = true
where organization_id is null and name in ('Consola de videojuegos', 'Consola portátil');

insert into public.device_types (name, category, attribute_group) values
  ('Notebook / Laptop','Computación','COMPUTER'), ('Impresora 3D','Impresión','PRINTER'),
  ('Plotter','Impresión','PRINTER'), ('Inversor','Energía','POWER'),
  ('Cámara de seguridad','Seguridad','CAMERA'), ('Auriculares / Headset','Audio y multimedia','AUDIO'),
  ('Barra de sonido','Audio y multimedia','AUDIO'), ('Micrófono','Audio y multimedia','AUDIO'),
  ('Caja registradora electrónica','Comercial','COMMERCIAL'), ('Balanza electrónica','Comercial','COMMERCIAL'),
  ('Dock','Periféricos','PERIPHERAL'), ('Hub USB','Periféricos','PERIPHERAL'),
  ('Power Bank','Energía','POWER'), ('Otro dispositivo electrónico','Personalizados','OTHER')
on conflict do nothing;

-- Categorías para filtrar primero las marcas relevantes, sin ocultar marcas globales sin categoría.
update public.device_brands set categories = array['Computación']
where organization_id is null and name in ('HP','Lenovo','Dell','Acer','ASUS','MSI','Samsung','Apple','Microsoft','Huawei','LG','Gigabyte','Razer','Toshiba','Dynabook','Fujitsu','Sony','Panasonic','Medion','Framework','Alienware','VAIO','CX','GFAST','EXO','Banghó','Positivo BGH','Chuwi','Teclast','Thomson','AVITA');
update public.device_brands set categories = array['Gaming']
where organization_id is null and name in ('Sony','Microsoft','Nintendo','ASUS','Lenovo','Razer');

-- Marcas que faltaban del catálogo base. Se mantienen editables mediante el catálogo privado.
insert into public.device_brands (name, categories) values
  ('Redmi', array['Telefonía y dispositivos móviles']), ('POCO', array['Telefonía y dispositivos móviles']),
  ('Honor', array['Telefonía y dispositivos móviles']), ('OPPO', array['Telefonía y dispositivos móviles']),
  ('Realme', array['Telefonía y dispositivos móviles']), ('OnePlus', array['Telefonía y dispositivos móviles']),
  ('Google', array['Telefonía y dispositivos móviles']), ('Nothing', array['Telefonía y dispositivos móviles']),
  ('Tecno', array['Telefonía y dispositivos móviles']), ('Infinix', array['Telefonía y dispositivos móviles']),
  ('CX', array['Computación']), ('GFAST', array['Computación']), ('EXO', array['Computación']),
  ('Banghó', array['Computación']), ('Positivo BGH', array['Computación']), ('Chuwi', array['Computación']),
  ('Teclast', array['Computación']), ('Thomson', array['Computación']), ('AVITA', array['Computación']),
  ('Dynabook', array['Computación']), ('Fujitsu', array['Computación']), ('Framework', array['Computación']),
  ('Medion', array['Computación']), ('VAIO', array['Computación']), ('Valve', array['Gaming'])
on conflict do nothing;

-- Familias comerciales reales y ampliables; no pretende ser un listado exhaustivo de SKUs.
with seeds(type_name, brand_name, model_name) as (values
  ('Notebook','HP','Essential'),('Notebook','HP','HP Laptop'),('Notebook','HP','Pavilion'),('Notebook','HP','Pavilion Plus'),('Notebook','HP','Pavilion x360'),('Notebook','HP','Envy'),('Notebook','HP','Envy x360'),('Notebook','HP','Spectre'),('Notebook','HP','Spectre x360'),('Notebook','HP','Victus'),('Notebook','HP','Omen'),('Notebook','HP','ProBook'),('Notebook','HP','EliteBook'),('Notebook','HP','EliteBook x360'),('Notebook','HP','ZBook'),('Notebook','HP','Chromebook'),('Notebook','HP','Dragonfly'),
  ('Notebook','Lenovo','IdeaPad'),('Notebook','Lenovo','IdeaPad Slim'),('Notebook','Lenovo','IdeaPad Flex'),('Notebook','Lenovo','Yoga'),('Notebook','Lenovo','ThinkPad'),('Notebook','Lenovo','ThinkBook'),('Notebook','Lenovo','Legion'),('Notebook','Lenovo','LOQ'),('Notebook','Lenovo','Chromebook'),
  ('Notebook','Dell','Inspiron'),('Notebook','Dell','XPS'),('Notebook','Dell','Latitude'),('Notebook','Dell','Precision'),('Notebook','Dell','Vostro'),('Notebook','Dell','Alienware'),('Notebook','Dell','G Series'),
  ('Notebook','Acer','Aspire'),('Notebook','Acer','Swift'),('Notebook','Acer','Spin'),('Notebook','Acer','TravelMate'),('Notebook','Acer','Extensa'),('Notebook','Acer','Nitro'),('Notebook','Acer','Predator'),('Notebook','Acer','Chromebook'),
  ('Notebook','ASUS','VivoBook'),('Notebook','ASUS','Zenbook'),('Notebook','ASUS','ExpertBook'),('Notebook','ASUS','ProArt'),('Notebook','ASUS','TUF Gaming'),('Notebook','ASUS','ROG'),('Notebook','ASUS','Chromebook'),
  ('Notebook','MSI','Modern'),('Notebook','MSI','Prestige'),('Notebook','MSI','Summit'),('Notebook','MSI','Creator'),('Notebook','MSI','Stealth'),('Notebook','MSI','Raider'),('Notebook','MSI','Vector'),('Notebook','MSI','Katana'),('Notebook','MSI','Cyborg'),('Notebook','MSI','Titan'),
  ('Notebook','Apple','MacBook'),('Notebook','Apple','MacBook Air'),('Notebook','Apple','MacBook Pro'),
  ('Notebook','Microsoft','Surface Laptop'),('Notebook','Microsoft','Surface Laptop Go'),('Notebook','Microsoft','Surface Book'),
  ('Notebook','Samsung','Galaxy Book'),('Notebook','Samsung','Galaxy Book Pro'),('Notebook','Samsung','Galaxy Book Ultra'),
  ('Notebook','Huawei','MateBook D'),('Notebook','Huawei','MateBook'),('Notebook','Huawei','MateBook X'),('Notebook','Huawei','MateBook X Pro'),
  ('Notebook','LG','Gram'),('Notebook','LG','Gram Style'),('Notebook','LG','Gram SuperSlim'),
  ('Notebook','Gigabyte','G5'),('Notebook','Gigabyte','G6'),('Notebook','Gigabyte','AERO'),('Notebook','Gigabyte','AORUS'),
  ('Notebook','Razer','Blade 14'),('Notebook','Razer','Blade 15'),('Notebook','Razer','Blade 16'),('Notebook','Razer','Blade 17'),('Notebook','Razer','Blade 18'),
  ('Notebook','Chuwi','HeroBook'),('Notebook','Chuwi','HeroBook Pro'),('Notebook','Chuwi','CoreBook'),('Notebook','Chuwi','CoreBook X'),('Notebook','Chuwi','GemiBook'),('Notebook','Chuwi','GemiBook Pro'),('Notebook','Chuwi','FreeBook'),('Notebook','Chuwi','MiniBook'),
  ('Notebook','Teclast','F7'),('Notebook','Teclast','F7 Plus'),('Notebook','Teclast','F15'),('Notebook','Teclast','F15 Plus'),('Notebook','Teclast','TBOLT'),
  ('Notebook','Thomson','Neo'),('Notebook','Thomson','Rox'),('Notebook','AVITA','Liber'),('Notebook','AVITA','Essential'),('Notebook','AVITA','Admiror'),
  ('Notebook','CX','CX 23200'),('Notebook','CX','CX 23500'),('Notebook','CX','CX Cloud'),('Notebook','GFAST','GFAST N-110'),('Notebook','GFAST','GFAST N-140'),('Notebook','GFAST','GFAST T-500'),('Notebook','EXO','EXO Smart'),('Notebook','EXO','EXO Wings'),('Notebook','EXO','EXO Ready'),('Notebook','Banghó','Bes'),('Notebook','Banghó','Max'),('Notebook','Banghó','Game Master'),('Notebook','Positivo BGH','AT300'),('Notebook','Positivo BGH','Serie A'),('Notebook','Positivo BGH','Serie C'),
  ('Consola de videojuegos','Sony','PlayStation / PS1'),('Consola de videojuegos','Sony','PS One'),('Consola de videojuegos','Sony','PlayStation 2 / PS2'),('Consola de videojuegos','Sony','PS2 Slim'),('Consola de videojuegos','Sony','PlayStation 3 Fat'),('Consola de videojuegos','Sony','PlayStation 3 Slim'),('Consola de videojuegos','Sony','PlayStation 3 Super Slim'),('Consola de videojuegos','Sony','PlayStation 4'),('Consola de videojuegos','Sony','PlayStation 4 Slim'),('Consola de videojuegos','Sony','PlayStation 4 Pro'),('Consola de videojuegos','Sony','PlayStation 5'),('Consola de videojuegos','Sony','PlayStation 5 Digital Edition'),('Consola de videojuegos','Sony','PlayStation 5 Slim'),('Consola de videojuegos','Sony','PlayStation 5 Pro'),
  ('Consola de videojuegos','Microsoft','Xbox'),('Consola de videojuegos','Microsoft','Xbox 360'),('Consola de videojuegos','Microsoft','Xbox 360 S'),('Consola de videojuegos','Microsoft','Xbox 360 E'),('Consola de videojuegos','Microsoft','Xbox One'),('Consola de videojuegos','Microsoft','Xbox One S'),('Consola de videojuegos','Microsoft','Xbox One X'),('Consola de videojuegos','Microsoft','Xbox Series S'),('Consola de videojuegos','Microsoft','Xbox Series X'),
  ('Consola de videojuegos','Nintendo','NES'),('Consola de videojuegos','Nintendo','SNES'),('Consola de videojuegos','Nintendo','Nintendo 64'),('Consola de videojuegos','Nintendo','GameCube'),('Consola de videojuegos','Nintendo','Wii'),('Consola de videojuegos','Nintendo','Wii U'),('Consola de videojuegos','Nintendo','Nintendo Switch'),('Consola de videojuegos','Nintendo','Nintendo Switch Lite'),('Consola de videojuegos','Nintendo','Nintendo Switch OLED'),
  ('Consola portátil','Nintendo','Game Boy'),('Consola portátil','Nintendo','Game Boy Color'),('Consola portátil','Nintendo','Game Boy Advance'),('Consola portátil','Nintendo','Nintendo DS'),('Consola portátil','Nintendo','Nintendo DSi'),('Consola portátil','Nintendo','Nintendo 3DS'),('Consola portátil','Nintendo','Nintendo 2DS'),('Consola portátil','Sony','PSP'),('Consola portátil','Sony','PS Vita'),('Consola portátil','Valve','Steam Deck'),('Consola portátil','Valve','Steam Deck OLED'),('Consola portátil','ASUS','ROG Ally'),('Consola portátil','Lenovo','Legion Go')
)
insert into public.device_models(device_type_id, brand_id, name)
select t.id, b.id, s.model_name from seeds s join public.device_types t on t.organization_id is null and t.name=s.type_name join public.device_brands b on b.organization_id is null and b.name=s.brand_name
on conflict do nothing;

create or replace function public.create_custom_device_brand_for_type(p_name text, p_type_id uuid)
returns setof public.device_brands language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_category text; v_id uuid;
begin
  select category into v_category from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org);
  if v_category is null then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_BRAND'; end if;
  select id into v_id from public.device_brands where (organization_id is null or organization_id=v_org) and lower(regexp_replace(trim(name),'\s+',' ','g'))=lower(v_name) order by organization_id nulls first limit 1;
  if v_id is not null then return query select * from public.device_brands where id=v_id; return; end if;
  insert into public.device_brands(organization_id,name,categories,created_by) values(v_org,v_name,array[v_category],auth.uid()) returning id into v_id;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_BRAND_CREATED','DEVICE_BRAND',v_id,jsonb_build_object('device_type_id',p_type_id));
  return query select * from public.device_brands where id=v_id;
end; $$;

create or replace function public.create_custom_device_model(p_name text, p_type_id uuid, p_brand_id uuid)
returns setof public.device_models language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin
  if char_length(v_name) not between 2 and 120 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
  perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if exists(select 1 from public.device_models where device_type_id=p_type_id and brand_id=p_brand_id and (organization_id is null or organization_id=v_org) and lower(regexp_replace(trim(name),'\s+',' ','g'))=lower(v_name)) then raise exception 'DEVICE_MODEL_EXISTS'; end if;
  insert into public.device_models(organization_id,device_type_id,brand_id,name,created_by) values(v_org,p_type_id,p_brand_id,v_name,auth.uid()) returning id into v_id;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_MODEL_CREATED','DEVICE_MODEL',v_id,jsonb_build_object('device_type_id',p_type_id,'brand_id',p_brand_id));
  return query select * from public.device_models where id=v_id;
end; $$;

create or replace function public.create_customer_device_with_catalog(p_customer_id uuid,p_type_id uuid,p_brand_id uuid,p_model_id uuid,p_model text,p_year text,p_color text,p_serial_number text,p_imei_1 text,p_imei_2 text,p_attributes jsonb,p_memories jsonb,p_storage_units jsonb,p_accessories text[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid; v_model text:=regexp_replace(trim(p_model),'\s+',' ','g');
begin
  perform 1 from public.customers where id=p_customer_id and organization_id=v_org; if not found then raise exception 'INVALID_CUSTOMER'; end if;
  perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
  perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if char_length(v_model) not between 2 and 120 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_model_id is not null then perform 1 from public.device_models where id=p_model_id and device_type_id=p_type_id and brand_id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_MODEL'; end if; end if;
  insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
  values(v_org,p_customer_id,p_type_id,p_brand_id,p_model_id,v_model,nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),nullif(trim(p_imei_1),''),nullif(trim(p_imei_2),''),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_id;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_id,jsonb_build_object('customer_id',p_customer_id,'model_id',p_model_id)); return v_id;
end; $$;

alter table public.device_models enable row level security;
create policy device_models_read_owner on public.device_models for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
grant select on public.device_models to authenticated;
revoke all on function public.create_custom_device_brand_for_type(text,uuid), public.create_custom_device_model(text,uuid,uuid), public.create_customer_device_with_catalog(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) from public, anon;
grant execute on function public.create_custom_device_brand_for_type(text,uuid), public.create_custom_device_model(text,uuid,uuid), public.create_customer_device_with_catalog(uuid,uuid,uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,jsonb,text[]) to authenticated;

comment on table public.device_models is 'Catálogo de modelos base o privados por organización; la fuente se deriva de organization_id nulo o no nulo.';
