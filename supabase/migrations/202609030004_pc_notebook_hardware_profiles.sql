-- PC and notebook hardware completion.  This migration is additive: it never
-- rewrites the already-applied repeatable-hardware migration or intake history.
begin;

create table if not exists public.ram_form_factors (
  id uuid primary key default gen_random_uuid(), code text not null unique,
  name text not null unique, is_active boolean not null default true
);
create table if not exists public.storage_capacities (
  id uuid primary key default gen_random_uuid(), capacity_gb integer not null unique check (capacity_gb > 0),
  label text not null unique, is_active boolean not null default true
);
create table if not exists public.hardware_catalog_items (
  id uuid primary key default gen_random_uuid(), category text not null check (category in (
    'MOTHERBOARD_BRAND','MOTHERBOARD_SOCKET','MOTHERBOARD_FORM_FACTOR','MOTHERBOARD_CHIPSET',
    'GPU_CHIP_BRAND','GPU_FAMILY','GPU_MODEL','GPU_BOARD_BRAND','PSU_BRAND','PSU_CERTIFICATION',
    'DISPLAY_SIZE','DISPLAY_RESOLUTION','DISPLAY_TECHNOLOGY','DISPLAY_REFRESH_RATE',
    'CHARGER_CONNECTOR','OPERATING_SYSTEM','PORT_CONNECTOR','PORT_PROTOCOL','WIFI_STANDARD',
    'CONNECTIVITY','CHECKLIST_STATUS')),
  code text not null, name text not null, parent_id uuid references public.hardware_catalog_items(id) on delete restrict,
  is_active boolean not null default true, unique(category, code)
);
create index if not exists ix_hardware_catalog_items_category on public.hardware_catalog_items(category, parent_id) where is_active;

-- A single row contains the non-repeatable physical components.  IDs remain
-- relational; free text is reserved only for model/serial values observed at intake.
create table if not exists public.customer_device_hardware_profiles (
  fk_customer_device_id uuid primary key references public.customer_devices(id) on delete restrict,
  fk_processor_model_id uuid references public.processor_models(id) on delete restrict,
  fk_motherboard_brand_id uuid references public.hardware_catalog_items(id) on delete restrict,
  motherboard_model text, fk_motherboard_socket_id uuid references public.hardware_catalog_items(id) on delete restrict,
  motherboard_chipset text, fk_motherboard_form_factor_id uuid references public.hardware_catalog_items(id) on delete restrict,
  gpu_mode text check (gpu_mode in ('INTEGRATED','DEDICATED')),
  fk_gpu_chip_brand_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_gpu_family_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_gpu_model_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_gpu_board_brand_id uuid references public.hardware_catalog_items(id) on delete restrict,
  gpu_vram_mb integer check (gpu_vram_mb is null or gpu_vram_mb > 0),
  psu_manufacturer text, psu_model text, psu_watts integer check (psu_watts is null or psu_watts > 0),
  fk_psu_certification_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_display_size_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_display_resolution_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_display_technology_id uuid references public.hardware_catalog_items(id) on delete restrict,
  fk_display_refresh_rate_id uuid references public.hardware_catalog_items(id) on delete restrict,
  display_touch boolean, display_condition text,
  battery_present boolean, battery_design_capacity_wh numeric(8,2) check (battery_design_capacity_wh is null or battery_design_capacity_wh > 0),
  battery_current_capacity_wh numeric(8,2) check (battery_current_capacity_wh is null or battery_current_capacity_wh >= 0),
  battery_cycles integer check (battery_cycles is null or battery_cycles >= 0), battery_visual_status text, battery_functional_status text,
  charger_delivered boolean, charger_kind text check (charger_kind in ('ORIGINAL','ALTERNATIVE')),
  charger_manufacturer text, charger_watts integer check (charger_watts is null or charger_watts > 0),
  charger_voltage numeric(7,2) check (charger_voltage is null or charger_voltage > 0), charger_amperage numeric(7,2) check (charger_amperage is null or charger_amperage > 0),
  fk_charger_connector_id uuid references public.hardware_catalog_items(id) on delete restrict, charger_condition text,
  updated_at timestamptz not null default now()
);
create table if not exists public.customer_device_ports (
  id uuid primary key default gen_random_uuid(), fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict,
  fk_port_connector_id uuid not null references public.hardware_catalog_items(id) on delete restrict,
  fk_port_protocol_id uuid references public.hardware_catalog_items(id) on delete restrict, quantity smallint not null default 1 check (quantity > 0), condition text,
  unique(fk_customer_device_id, fk_port_connector_id, fk_port_protocol_id)
);
create table if not exists public.customer_device_connectivity (
  id uuid primary key default gen_random_uuid(), fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict,
  fk_connectivity_id uuid not null references public.hardware_catalog_items(id) on delete restrict,
  fk_wifi_standard_id uuid references public.hardware_catalog_items(id) on delete restrict, condition text,
  unique(fk_customer_device_id, fk_connectivity_id, fk_wifi_standard_id)
);
create table if not exists public.customer_device_checklist_items (
  id uuid primary key default gen_random_uuid(), fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict,
  item_key text not null check (item_key ~ '^[a-z][a-z0-9_]{1,80}$'), status text not null check (status in ('CORRECT','FAULT','NOT_TESTED','NOT_APPLICABLE')),
  observation text, unique(fk_customer_device_id, item_key)
);

alter table public.customer_device_ram_modules add column if not exists fk_ram_form_factor_id uuid references public.ram_form_factors(id) on delete restrict;
alter table public.customer_device_ram_modules add column if not exists updated_at timestamptz not null default now();
alter table public.customer_device_storage_drives add column if not exists fk_storage_capacity_id uuid references public.storage_capacities(id) on delete restrict;
alter table public.customer_device_storage_drives add column if not exists updated_at timestamptz not null default now();

insert into public.ram_form_factors(code,name) values ('dimm','DIMM'),('so_dimm','SO-DIMM'),('onboard','Onboard / Soldada') on conflict(code) do update set is_active=true;
insert into public.storage_capacities(capacity_gb,label) values
 (32,'32 GB'),(64,'64 GB'),(120,'120 GB'),(128,'128 GB'),(240,'240 GB'),(250,'250 GB'),(256,'256 GB'),(480,'480 GB'),(500,'500 GB'),(512,'512 GB'),(960,'960 GB'),(1024,'1 TB'),(2048,'2 TB'),(4096,'4 TB'),(8192,'8 TB')
on conflict(capacity_gb) do update set is_active=true;
insert into public.ram_types(code,name) values ('lpddr3','LPDDR3'),('lpddr4','LPDDR4'),('lpddr4x','LPDDR4X'),('lpddr5','LPDDR5'),('lpddr5x','LPDDR5X') on conflict(code) do update set is_active=true;
insert into public.ram_speeds(fk_ram_type_id,mhz)
select r.id,v.mhz from public.ram_types r join (values
 ('ddr3',1866),('ddr3',2133),('ddr4',2933),('ddr4',3000),
 ('lpddr3',1600),('lpddr4',2133),('lpddr4',2666),('lpddr4x',3200),('lpddr4x',4266),('lpddr5',4800),('lpddr5',5500),('lpddr5x',6400),('lpddr5x',7467)
) v(code,mhz) on r.code=v.code on conflict do nothing;

insert into public.hardware_catalog_items(category,code,name) values
 ('MOTHERBOARD_BRAND','asus','ASUS'),('MOTHERBOARD_BRAND','asrock','ASRock'),('MOTHERBOARD_BRAND','gigabyte','Gigabyte'),('MOTHERBOARD_BRAND','msi','MSI'),('MOTHERBOARD_BRAND','biostar','Biostar'),('MOTHERBOARD_BRAND','evga','EVGA'),
 ('MOTHERBOARD_SOCKET','am2','AM2'),('MOTHERBOARD_SOCKET','am2_plus','AM2+'),('MOTHERBOARD_SOCKET','am3','AM3'),('MOTHERBOARD_SOCKET','am3_plus','AM3+'),('MOTHERBOARD_SOCKET','am4','AM4'),('MOTHERBOARD_SOCKET','am5','AM5'),('MOTHERBOARD_SOCKET','fm1','FM1'),('MOTHERBOARD_SOCKET','fm2','FM2'),('MOTHERBOARD_SOCKET','fm2_plus','FM2+'),
 ('MOTHERBOARD_SOCKET','lga775','LGA 775'),('MOTHERBOARD_SOCKET','lga1156','LGA 1156'),('MOTHERBOARD_SOCKET','lga1155','LGA 1155'),('MOTHERBOARD_SOCKET','lga1150','LGA 1150'),('MOTHERBOARD_SOCKET','lga1151','LGA 1151'),('MOTHERBOARD_SOCKET','lga1200','LGA 1200'),('MOTHERBOARD_SOCKET','lga1700','LGA 1700'),('MOTHERBOARD_SOCKET','lga1851','LGA 1851'),('MOTHERBOARD_SOCKET','lga2011','LGA 2011'),('MOTHERBOARD_SOCKET','lga2011_3','LGA 2011-3'),('MOTHERBOARD_SOCKET','lga2066','LGA 2066'),
 ('MOTHERBOARD_FORM_FACTOR','atx','ATX'),('MOTHERBOARD_FORM_FACTOR','micro_atx','Micro-ATX'),('MOTHERBOARD_FORM_FACTOR','mini_itx','Mini-ITX'),('MOTHERBOARD_FORM_FACTOR','e_atx','E-ATX'),
 ('GPU_CHIP_BRAND','nvidia','NVIDIA'),('GPU_CHIP_BRAND','amd','AMD'),('GPU_CHIP_BRAND','intel','Intel'),('GPU_FAMILY','geforce_gt','GeForce GT'),('GPU_FAMILY','geforce_gtx','GeForce GTX'),('GPU_FAMILY','geforce_rtx','GeForce RTX'),('GPU_FAMILY','radeon','Radeon'),('GPU_FAMILY','radeon_rx','Radeon RX'),('GPU_FAMILY','intel_arc','Intel Arc'),
 ('PSU_CERTIFICATION','none','Sin certificación'),('PSU_CERTIFICATION','80_plus','80 PLUS'),('PSU_CERTIFICATION','bronze','80 PLUS Bronze'),('PSU_CERTIFICATION','silver','80 PLUS Silver'),('PSU_CERTIFICATION','gold','80 PLUS Gold'),('PSU_CERTIFICATION','platinum','80 PLUS Platinum'),('PSU_CERTIFICATION','titanium','80 PLUS Titanium'),
 ('DISPLAY_TECHNOLOGY','tn','TN'),('DISPLAY_TECHNOLOGY','ips','IPS'),('DISPLAY_TECHNOLOGY','va','VA'),('DISPLAY_TECHNOLOGY','oled','OLED'),('DISPLAY_TECHNOLOGY','mini_led','Mini-LED'),
 ('CHARGER_CONNECTOR','barrel','Barrel / cilíndrico'),('CHARGER_CONNECTOR','usb_c','USB-C'),('CHARGER_CONNECTOR','magsafe','MagSafe'),('CHARGER_CONNECTOR','proprietary','Propietario'),
 ('CONNECTIVITY','ethernet','Ethernet'),('CONNECTIVITY','wifi','Wi-Fi'),('CONNECTIVITY','bluetooth','Bluetooth'),
 ('WIFI_STANDARD','802_11b','802.11b'),('WIFI_STANDARD','802_11g','802.11g'),('WIFI_STANDARD','802_11n','802.11n'),('WIFI_STANDARD','wifi_5','Wi-Fi 5 / 802.11ac'),('WIFI_STANDARD','wifi_6','Wi-Fi 6 / 802.11ax'),('WIFI_STANDARD','wifi_6e','Wi-Fi 6E'),('WIFI_STANDARD','wifi_7','Wi-Fi 7')
on conflict(category,code) do update set is_active=true;
insert into public.hardware_catalog_items(category,code,name)
select 'DISPLAY_SIZE',replace(v,'"','in'),v from unnest(array['10.1"','11.6"','12"','12.5"','13"','13.3"','13.6"','14"','14.5"','15"','15.6"','16"','16.1"','17"','17.3"','18"']) v
on conflict(category,code) do update set is_active=true;
insert into public.hardware_catalog_items(category,code,name)
select 'DISPLAY_RESOLUTION',replace(replace(v,'×','x'),' ','_'),v from unnest(array['1024×600','1366×768','1600×900','1920×1080','1920×1200','2256×1504','2560×1440','2560×1600','2880×1800','3200×1800','3840×2160']) v
on conflict(category,code) do update set is_active=true;
insert into public.hardware_catalog_items(category,code,name)
select 'DISPLAY_REFRESH_RATE',replace(v,' ','_'),v from unnest(array['60 Hz','75 Hz','90 Hz','120 Hz','144 Hz','165 Hz','240 Hz']) v
on conflict(category,code) do update set is_active=true;
insert into public.hardware_catalog_items(category,code,name)
select 'PORT_CONNECTOR',lower(regexp_replace(v,'[^a-zA-Z0-9]+','_','g')),v from unnest(array['USB-A','USB-B','Mini-USB','Micro-USB','USB-C','VGA','DVI','HDMI','Mini HDMI','DisplayPort','Mini DisplayPort','Ethernet RJ45','Audio 3.5 mm','SD','microSD','PS/2','Serial','Paralelo']) v
on conflict(category,code) do update set is_active=true;
insert into public.hardware_catalog_items(category,code,name)
select 'OPERATING_SYSTEM',lower(regexp_replace(v,'[^a-zA-Z0-9]+','_','g')),v from unnest(array['Windows XP','Windows Vista','Windows 7','Windows 8','Windows 8.1','Windows 10','Windows 11','Ubuntu','Debian','Linux Mint','Fedora','Arch Linux','Otro Linux','Sin sistema operativo','No determinado']) v
on conflict(category,code) do update set is_active=true;

alter table public.ram_form_factors enable row level security;
alter table public.storage_capacities enable row level security;
alter table public.hardware_catalog_items enable row level security;
alter table public.customer_device_hardware_profiles enable row level security;
alter table public.customer_device_ports enable row level security;
alter table public.customer_device_connectivity enable row level security;
alter table public.customer_device_checklist_items enable row level security;
create policy ram_form_factors_read on public.ram_form_factors for select to authenticated using(is_active);
create policy storage_capacities_read on public.storage_capacities for select to authenticated using(is_active);
create policy hardware_catalog_items_read on public.hardware_catalog_items for select to authenticated using(is_active);
create policy customer_device_hardware_profiles_read on public.customer_device_hardware_profiles for select to authenticated using(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()));
create policy customer_device_ports_read on public.customer_device_ports for select to authenticated using(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()));
create policy customer_device_connectivity_read on public.customer_device_connectivity for select to authenticated using(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()));
create policy customer_device_checklist_items_read on public.customer_device_checklist_items for select to authenticated using(exists(select 1 from public.customer_devices d where d.id=fk_customer_device_id and d.fk_organizacion_id=public.current_organization_id()));
revoke insert,update,delete on public.ram_form_factors,public.storage_capacities,public.hardware_catalog_items,public.customer_device_hardware_profiles,public.customer_device_ports,public.customer_device_connectivity,public.customer_device_checklist_items from anon,authenticated;

commit;
