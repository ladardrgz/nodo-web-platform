-- Stable domain identity and CPU generation hierarchy.  Labels remain editable
-- presentation data; business logic must use device_types.code.
begin;

alter table public.device_types add column if not exists code text;
update public.device_types
set code = case normalized_name
  when 'desktop pc' then 'desktop_pc'
  when 'notebook' then 'notebook'
end
where code is null;
alter table public.device_types alter column code set not null;
alter table public.device_types add constraint uq_device_types_code unique (code);
alter table public.device_types add constraint ck_device_types_code check (code ~ '^[a-z][a-z0-9_]{1,62}$');

create table if not exists public.processor_generations (
  id uuid primary key default gen_random_uuid(),
  fk_processor_family_id uuid not null references public.processor_families(id) on delete restrict,
  code text not null check (code ~ '^[a-z0-9_]+$'),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  sort_order smallint not null check (sort_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (fk_processor_family_id, code)
);
create index if not exists ix_processor_generations_family on public.processor_generations(fk_processor_family_id, sort_order) where is_active;
alter table public.processor_generations enable row level security;
create policy processor_generations_read on public.processor_generations for select to authenticated using (is_active);
revoke insert, update, delete on public.processor_generations from anon, authenticated;

alter table public.processor_models add column if not exists fk_processor_generation_id uuid references public.processor_generations(id) on delete restrict;
create index if not exists ix_processor_models_generation on public.processor_models(fk_processor_generation_id) where activo;

-- Idempotent, relational seeds. Families are resolved by their unique natural
-- key; no UUID literals or presentation labels are persisted as relationships.
insert into public.processor_generations(fk_processor_family_id, code, name, sort_order)
select f.id, g.code, g.name, g.sort_order
from public.processor_families f
join public.processor_brands b on b.id = f.fk_marca_procesador_id
join (values
 ('AMD','Ryzen 3','1000','Series 1000',10),('AMD','Ryzen 3','2000','Series 2000',20),('AMD','Ryzen 3','3000','Series 3000',30),('AMD','Ryzen 3','4000','Series 4000',40),('AMD','Ryzen 3','5000','Series 5000',50),('AMD','Ryzen 3','7000','Series 7000',70),('AMD','Ryzen 3','8000','Series 8000',80),('AMD','Ryzen 3','9000','Series 9000',90),
 ('AMD','Ryzen 5','1000','Series 1000',10),('AMD','Ryzen 5','2000','Series 2000',20),('AMD','Ryzen 5','3000','Series 3000',30),('AMD','Ryzen 5','4000','Series 4000',40),('AMD','Ryzen 5','5000','Series 5000',50),('AMD','Ryzen 5','7000','Series 7000',70),('AMD','Ryzen 5','8000','Series 8000',80),('AMD','Ryzen 5','9000','Series 9000',90),
 ('AMD','Ryzen 7','1000','Series 1000',10),('AMD','Ryzen 7','2000','Series 2000',20),('AMD','Ryzen 7','3000','Series 3000',30),('AMD','Ryzen 7','4000','Series 4000',40),('AMD','Ryzen 7','5000','Series 5000',50),('AMD','Ryzen 7','7000','Series 7000',70),('AMD','Ryzen 7','8000','Series 8000',80),('AMD','Ryzen 7','9000','Series 9000',90),
 ('AMD','Ryzen 9','3000','Series 3000',30),('AMD','Ryzen 9','5000','Series 5000',50),('AMD','Ryzen 9','7000','Series 7000',70),('AMD','Ryzen 9','9000','Series 9000',90),
 ('Intel','Core i3','gen_1','1st generation',10),('Intel','Core i3','gen_2','2nd generation',20),('Intel','Core i3','gen_3','3rd generation',30),('Intel','Core i3','gen_4','4th generation',40),('Intel','Core i3','gen_5','5th generation',50),('Intel','Core i3','gen_6','6th generation',60),('Intel','Core i3','gen_7','7th generation',70),('Intel','Core i3','gen_8','8th generation',80),('Intel','Core i3','gen_9','9th generation',90),('Intel','Core i3','gen_10','10th generation',100),('Intel','Core i3','gen_11','11th generation',110),('Intel','Core i3','gen_12','12th generation',120),('Intel','Core i3','gen_13','13th generation',130),('Intel','Core i3','gen_14','14th generation',140),
 ('Intel','Core i5','gen_1','1st generation',10),('Intel','Core i5','gen_2','2nd generation',20),('Intel','Core i5','gen_3','3rd generation',30),('Intel','Core i5','gen_4','4th generation',40),('Intel','Core i5','gen_5','5th generation',50),('Intel','Core i5','gen_6','6th generation',60),('Intel','Core i5','gen_7','7th generation',70),('Intel','Core i5','gen_8','8th generation',80),('Intel','Core i5','gen_9','9th generation',90),('Intel','Core i5','gen_10','10th generation',100),('Intel','Core i5','gen_11','11th generation',110),('Intel','Core i5','gen_12','12th generation',120),('Intel','Core i5','gen_13','13th generation',130),('Intel','Core i5','gen_14','14th generation',140),
 ('Intel','Core i7','gen_2','2nd generation',20),('Intel','Core i7','gen_3','3rd generation',30),('Intel','Core i7','gen_4','4th generation',40),('Intel','Core i7','gen_6','6th generation',60),('Intel','Core i7','gen_7','7th generation',70),('Intel','Core i7','gen_8','8th generation',80),('Intel','Core i7','gen_9','9th generation',90),('Intel','Core i7','gen_10','10th generation',100),('Intel','Core i7','gen_11','11th generation',110),('Intel','Core i7','gen_12','12th generation',120),('Intel','Core i7','gen_13','13th generation',130),('Intel','Core i7','gen_14','14th generation',140),
 ('Intel','Core i9','gen_9','9th generation',90),('Intel','Core i9','gen_10','10th generation',100),('Intel','Core i9','gen_11','11th generation',110),('Intel','Core i9','gen_12','12th generation',120),('Intel','Core i9','gen_13','13th generation',130),('Intel','Core i9','gen_14','14th generation',140)
) as g(brand_name, family_name, code, name, sort_order) on b.nombre = g.brand_name and f.nombre = g.family_name
on conflict (fk_processor_family_id, code) do update set name=excluded.name,sort_order=excluded.sort_order,is_active=true;

-- Backfill only records whose generation is unambiguous from their documented
-- model naming; unknown data remains null rather than being fabricated.
update public.processor_models m set fk_processor_generation_id=g.id
from public.processor_families f join public.processor_brands b on b.id=f.fk_marca_procesador_id
join public.processor_generations g on g.fk_processor_family_id=f.id
where m.fk_familia_procesador_id=f.id and m.fk_processor_generation_id is null
  and ((b.nombre='AMD' and m.nombre ~ ('^' || replace(g.code,'_','') ))
    or (b.nombre='Intel' and m.nombre ~ ('^i[357]-' || substring(g.code from 5) || '[0-9]')));

commit;
