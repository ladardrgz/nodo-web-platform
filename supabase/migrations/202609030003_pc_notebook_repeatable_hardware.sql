-- Normalized repeatable hardware records. Catalog values are FK-backed; no
-- technical strings are used as the only persisted representation.
begin;

create table if not exists public.ram_types (id uuid primary key default gen_random_uuid(), code text not null unique, name text not null unique, is_active boolean not null default true);
create table if not exists public.ram_speeds (id uuid primary key default gen_random_uuid(), fk_ram_type_id uuid not null references public.ram_types(id) on delete restrict, mhz integer not null check(mhz between 100 and 20000), is_active boolean not null default true, unique(fk_ram_type_id,mhz));
create table if not exists public.storage_interfaces (id uuid primary key default gen_random_uuid(), code text not null unique, name text not null unique, is_active boolean not null default true);
create table if not exists public.storage_form_factors (id uuid primary key default gen_random_uuid(), code text not null unique, name text not null unique, is_active boolean not null default true);
create table if not exists public.customer_device_ram_modules (id uuid primary key default gen_random_uuid(), fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict, fk_ram_type_id uuid not null references public.ram_types(id) on delete restrict, fk_ram_speed_id uuid references public.ram_speeds(id) on delete restrict, capacity_mb integer not null check(capacity_mb>0), form_factor text, is_soldered boolean not null default false, manufacturer text, model text, created_at timestamptz not null default now());
create table if not exists public.customer_device_storage_drives (id uuid primary key default gen_random_uuid(), fk_customer_device_id uuid not null references public.customer_devices(id) on delete restrict, fk_storage_type_id uuid references public.storage_types(id) on delete restrict, fk_storage_interface_id uuid references public.storage_interfaces(id) on delete restrict, fk_storage_form_factor_id uuid references public.storage_form_factors(id) on delete restrict, capacity_gb integer check(capacity_gb>0), manufacturer text, model text, serial_number text, condition text, created_at timestamptz not null default now());
create index if not exists ix_customer_device_ram_modules_device on public.customer_device_ram_modules(fk_customer_device_id);
create index if not exists ix_customer_device_storage_drives_device on public.customer_device_storage_drives(fk_customer_device_id);
alter table public.ram_types enable row level security; alter table public.ram_speeds enable row level security; alter table public.storage_interfaces enable row level security; alter table public.storage_form_factors enable row level security;
create policy ram_types_read on public.ram_types for select to authenticated using(is_active);
create policy ram_speeds_read on public.ram_speeds for select to authenticated using(is_active);
create policy storage_interfaces_read on public.storage_interfaces for select to authenticated using(is_active);
create policy storage_form_factors_read on public.storage_form_factors for select to authenticated using(is_active);
revoke insert,update,delete on public.ram_types,public.ram_speeds,public.storage_interfaces,public.storage_form_factors from anon,authenticated;
insert into public.ram_types(code,name) values ('ddr','DDR'),('ddr2','DDR2'),('ddr3','DDR3'),('ddr4','DDR4'),('ddr5','DDR5') on conflict(code) do update set is_active=true;
insert into public.ram_speeds(fk_ram_type_id,mhz) select r.id,v.mhz from public.ram_types r join (values('ddr3',800),('ddr3',1066),('ddr3',1333),('ddr3',1600),('ddr4',2133),('ddr4',2400),('ddr4',2666),('ddr4',3200),('ddr4',3600),('ddr5',4800),('ddr5',5200),('ddr5',5600),('ddr5',6000),('ddr5',6400))v(code,mhz) on r.code=v.code on conflict do nothing;
insert into public.storage_interfaces(code,name) values('sata','SATA'),('sata_ii','SATA II'),('sata_iii','SATA III'),('ide_pata','IDE / PATA'),('msata','mSATA'),('m2_sata','M.2 SATA'),('m2_nvme_pcie','M.2 NVMe / PCIe') on conflict(code) do update set is_active=true;
insert into public.storage_form_factors(code,name) values('3_5','3.5 inch'),('2_5','2.5 inch'),('m2_2230','M.2 2230'),('m2_2242','M.2 2242'),('m2_2260','M.2 2260'),('m2_2280','M.2 2280') on conflict(code) do update set is_active=true;
commit;
