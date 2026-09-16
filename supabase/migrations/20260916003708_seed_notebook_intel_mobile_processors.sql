-- Curated Intel mobile processor catalog for Notebook intake.
-- Source taxonomy: Intel official mobile processor documentation/product briefs.
-- This migration records commercial identity and Notebook compatibility only.
-- It intentionally leaves electrical and performance specifications null.
begin;

-- Families are shared global catalog entities.  The series/generation layer keeps
-- the cascaded selector precise without duplicating the Intel manufacturer.
with intel_brand as (
  select id from public.processor_brands where nombre_normalizado = public.normalizar_nombre_catalogo('Intel')
), requested_families(nombre) as (values
  ('Celeron'), ('Pentium'), ('Processor'),
  ('Core i3'), ('Core i5'), ('Core i7'), ('Core i9'),
  ('Core 3'), ('Core 5'), ('Core 7'),
  ('Core Ultra 5'), ('Core Ultra 7'), ('Core Ultra 9')
)
insert into public.processor_families (fk_marca_procesador_id, nombre, activo)
select b.id, f.nombre, true
from intel_brand b cross join requested_families f
where not exists (
  select 1 from public.processor_families existing
  where existing.fk_marca_procesador_id = b.id
    and existing.nombre_normalizado = public.normalizar_nombre_catalogo(f.nombre)
);

with requested_generations(family_name, code, name, sort_order) as (values
  ('Celeron', 'm', 'Celeron M', 10),
  ('Celeron', '1000', '1000 Series', 20), ('Celeron', '2000', '2000 Series', 30),
  ('Celeron', '3000', '3000 Series', 40), ('Celeron', '4000', '4000 Series', 50),
  ('Celeron', '5000', '5000 Series', 60), ('Celeron', '6000', '6000 Series', 70),
  ('Celeron', 'n_series', 'N Series', 80),
  ('Pentium', 'b', 'Pentium B', 10), ('Pentium', 'n', 'Pentium N', 20),
  ('Pentium', '2000', '2000 Series', 30), ('Pentium', '3000', '3000 Series', 40),
  ('Pentium', '4000', '4000 Series', 50), ('Pentium', 'silver', 'Pentium Silver', 60),
  ('Pentium', 'gold', 'Pentium Gold', 70),
  ('Processor', 'n_series', 'N Series', 10),
  ('Core i3', 'gen_2', '2nd generation', 20), ('Core i3', 'gen_3', '3rd generation', 30),
  ('Core i3', 'gen_4', '4th generation', 40), ('Core i3', 'gen_5', '5th generation', 50),
  ('Core i3', 'gen_6', '6th generation', 60), ('Core i3', 'gen_7', '7th generation', 70),
  ('Core i3', 'gen_8', '8th generation', 80), ('Core i3', 'gen_10', '10th generation', 100),
  ('Core i3', 'gen_11', '11th generation', 110), ('Core i3', 'gen_12', '12th generation', 120),
  ('Core i3', 'gen_13', '13th generation', 130), ('Core i3', 'gen_14', '14th generation', 140),
  ('Core i5', 'gen_2', '2nd generation', 20), ('Core i5', 'gen_3', '3rd generation', 30),
  ('Core i5', 'gen_4', '4th generation', 40), ('Core i5', 'gen_5', '5th generation', 50),
  ('Core i5', 'gen_6', '6th generation', 60), ('Core i5', 'gen_7', '7th generation', 70),
  ('Core i5', 'gen_8', '8th generation', 80), ('Core i5', 'gen_9', '9th generation', 90),
  ('Core i5', 'gen_10', '10th generation', 100), ('Core i5', 'gen_11', '11th generation', 110),
  ('Core i5', 'gen_12', '12th generation', 120), ('Core i5', 'gen_13', '13th generation', 130), ('Core i5', 'gen_14', '14th generation', 140),
  ('Core i7', 'gen_2', '2nd generation', 20), ('Core i7', 'gen_3', '3rd generation', 30),
  ('Core i7', 'gen_4', '4th generation', 40), ('Core i7', 'gen_5', '5th generation', 50),
  ('Core i7', 'gen_6', '6th generation', 60), ('Core i7', 'gen_7', '7th generation', 70),
  ('Core i7', 'gen_8', '8th generation', 80), ('Core i7', 'gen_9', '9th generation', 90),
  ('Core i7', 'gen_10', '10th generation', 100), ('Core i7', 'gen_11', '11th generation', 110),
  ('Core i7', 'gen_12', '12th generation', 120), ('Core i7', 'gen_13', '13th generation', 130), ('Core i7', 'gen_14', '14th generation', 140),
  ('Core i9', 'gen_8', '8th generation', 80), ('Core i9', 'gen_9', '9th generation', 90),
  ('Core i9', 'gen_10', '10th generation', 100), ('Core i9', 'gen_11', '11th generation', 110),
  ('Core i9', 'gen_12', '12th generation', 120), ('Core i9', 'gen_13', '13th generation', 130), ('Core i9', 'gen_14', '14th generation', 140),
  ('Core 3', 'series_1', 'Series 1', 10), ('Core 5', 'series_1', 'Series 1', 10),
  ('Core 5', 'series_2', 'Series 2', 20), ('Core 7', 'series_1', 'Series 1', 10), ('Core 7', 'series_2', 'Series 2', 20),
  ('Core Ultra 5', 'series_1', 'Series 1', 10), ('Core Ultra 5', 'series_2', 'Series 2', 20),
  ('Core Ultra 7', 'series_1', 'Series 1', 10), ('Core Ultra 7', 'series_2', 'Series 2', 20),
  ('Core Ultra 9', 'series_1', 'Series 1', 10), ('Core Ultra 9', 'series_2', 'Series 2', 20)
)
insert into public.processor_generations (fk_processor_family_id, code, name, sort_order, is_active)
select f.id, g.code, g.name, g.sort_order, true
from requested_generations g
join public.processor_families f on f.nombre_normalizado = public.normalizar_nombre_catalogo(g.family_name)
join public.processor_brands b on b.id = f.fk_marca_procesador_id and b.nombre_normalizado = public.normalizar_nombre_catalogo('Intel')
where not exists (
  select 1 from public.processor_generations existing
  where existing.fk_processor_family_id = f.id and existing.code = g.code
);

with requested_models(family_name, generation_code, nombre) as (values
  -- Celeron M and successive mobile series
  ('Celeron','m','Celeron M 350'), ('Celeron','m','Celeron M 360'), ('Celeron','m','Celeron M 370'), ('Celeron','m','Celeron M 380'), ('Celeron','m','Celeron M 390'),
  ('Celeron','1000','Celeron 1000M'), ('Celeron','1000','Celeron 1005M'), ('Celeron','1000','Celeron 1007U'),
  ('Celeron','2000','Celeron 2955U'), ('Celeron','2000','Celeron 2957U'), ('Celeron','2000','Celeron 2961Y'), ('Celeron','2000','Celeron 2980U'),
  ('Celeron','3000','Celeron 3205U'), ('Celeron','3000','Celeron 3215U'), ('Celeron','3000','Celeron 3755U'), ('Celeron','3000','Celeron 3855U'), ('Celeron','3000','Celeron 3865U'), ('Celeron','3000','Celeron 3965U'),
  ('Celeron','4000','Celeron 4000'), ('Celeron','4000','Celeron 4025U'), ('Celeron','4000','Celeron 4105U'), ('Celeron','4000','Celeron 4205U'), ('Celeron','4000','Celeron 4305U'),
  ('Celeron','5000','Celeron 5205U'), ('Celeron','5000','Celeron 5305U'),
  ('Celeron','6000','Celeron 6305'), ('Celeron','6000','Celeron 6305E'),
  ('Celeron','n_series','Celeron N2805'), ('Celeron','n_series','Celeron N2810'), ('Celeron','n_series','Celeron N2830'), ('Celeron','n_series','Celeron N2840'), ('Celeron','n_series','Celeron N2930'), ('Celeron','n_series','Celeron N2940'),
  ('Celeron','n_series','Celeron N3010'), ('Celeron','n_series','Celeron N3050'), ('Celeron','n_series','Celeron N3060'), ('Celeron','n_series','Celeron N3150'), ('Celeron','n_series','Celeron N3160'),
  ('Celeron','n_series','Celeron N3350'), ('Celeron','n_series','Celeron N3450'), ('Celeron','n_series','Celeron N4000'), ('Celeron','n_series','Celeron N4020'), ('Celeron','n_series','Celeron N4100'), ('Celeron','n_series','Celeron N4120'),
  ('Celeron','n_series','Celeron N4500'), ('Celeron','n_series','Celeron N4505'), ('Celeron','n_series','Celeron N5100'), ('Celeron','n_series','Celeron N5105'),
  -- Pentium mobile: B, N, legacy numbered lines, Silver and Gold
  ('Pentium','b','Pentium B940'), ('Pentium','b','Pentium B950'), ('Pentium','b','Pentium B960'), ('Pentium','b','Pentium B970'), ('Pentium','b','Pentium B980'),
  ('Pentium','n','Pentium N3510'), ('Pentium','n','Pentium N3520'), ('Pentium','n','Pentium N3530'), ('Pentium','n','Pentium N3540'), ('Pentium','n','Pentium N3700'), ('Pentium','n','Pentium N3710'), ('Pentium','n','Pentium N4200'),
  ('Pentium','2000','Pentium 2020M'), ('Pentium','2000','Pentium 2030M'), ('Pentium','2000','Pentium 2117U'), ('Pentium','2000','Pentium 2127U'),
  ('Pentium','3000','Pentium 3556U'), ('Pentium','3000','Pentium 3558U'),
  ('Pentium','4000','Pentium 3805U'), ('Pentium','4000','Pentium 3825U'),
  ('Pentium','silver','Pentium Silver N5000'), ('Pentium','silver','Pentium Silver N5030'), ('Pentium','silver','Pentium Silver N6000'), ('Pentium','silver','Pentium Silver N6005'),
  ('Pentium','gold','Pentium Gold 4415U'), ('Pentium','gold','Pentium Gold 4417U'), ('Pentium','gold','Pentium Gold 5405U'), ('Pentium','gold','Pentium Gold 6405U'), ('Pentium','gold','Pentium Gold 6500Y'), ('Pentium','gold','Pentium Gold 7505'), ('Pentium','gold','Pentium Gold 8505'),
  -- Current entry-level Intel Processor N series
  ('Processor','n_series','Intel Processor N50'), ('Processor','n_series','Intel Processor N95'), ('Processor','n_series','Intel Processor N97'), ('Processor','n_series','Intel Processor N100'), ('Processor','n_series','Intel Processor N150'), ('Processor','n_series','Intel Processor N200'), ('Processor','n_series','Intel Processor N250'), ('Processor','n_series','Intel Processor N305'), ('Processor','n_series','Intel Processor N350'),
  -- Core i3 mobile, generations 2 through 14 where mobile parts are catalogued
  ('Core i3','gen_2','Core i3-2310M'), ('Core i3','gen_2','Core i3-2330M'), ('Core i3','gen_2','Core i3-2350M'),
  ('Core i3','gen_3','Core i3-3110M'), ('Core i3','gen_3','Core i3-3120M'), ('Core i3','gen_3','Core i3-3217U'), ('Core i3','gen_3','Core i3-3227U'),
  ('Core i3','gen_4','Core i3-4005U'), ('Core i3','gen_4','Core i3-4010U'), ('Core i3','gen_4','Core i3-4030U'),
  ('Core i3','gen_5','Core i3-5005U'), ('Core i3','gen_5','Core i3-5010U'),
  ('Core i3','gen_6','Core i3-6006U'), ('Core i3','gen_6','Core i3-6100U'),
  ('Core i3','gen_7','Core i3-7100U'), ('Core i3','gen_7','Core i3-7130U'),
  ('Core i3','gen_8','Core i3-8130U'), ('Core i3','gen_8','Core i3-8145U'),
  ('Core i3','gen_10','Core i3-1005G1'), ('Core i3','gen_10','Core i3-10110U'),
  ('Core i3','gen_11','Core i3-1115G4'), ('Core i3','gen_11','Core i3-1125G4'),
  ('Core i3','gen_12','Core i3-1215U'), ('Core i3','gen_12','Core i3-1220P'),
  ('Core i3','gen_13','Core i3-1315U'), ('Core i3','gen_13','Core i3-1305U'),
  ('Core i3','gen_14','Core i3-1415U'),
  -- Core i5 mobile
  ('Core i5','gen_2','Core i5-2410M'), ('Core i5','gen_2','Core i5-2430M'), ('Core i5','gen_2','Core i5-2450M'),
  ('Core i5','gen_3','Core i5-3210M'), ('Core i5','gen_3','Core i5-3230M'), ('Core i5','gen_3','Core i5-3317U'), ('Core i5','gen_3','Core i5-3337U'),
  ('Core i5','gen_4','Core i5-4200U'), ('Core i5','gen_4','Core i5-4210U'), ('Core i5','gen_4','Core i5-4250U'), ('Core i5','gen_4','Core i5-4300U'), ('Core i5','gen_4','Core i5-4310U'),
  ('Core i5','gen_5','Core i5-5200U'), ('Core i5','gen_5','Core i5-5250U'), ('Core i5','gen_5','Core i5-5300U'),
  ('Core i5','gen_6','Core i5-6200U'), ('Core i5','gen_6','Core i5-6300U'), ('Core i5','gen_6','Core i5-6440HQ'),
  ('Core i5','gen_7','Core i5-7200U'), ('Core i5','gen_7','Core i5-7300U'),
  ('Core i5','gen_8','Core i5-8250U'), ('Core i5','gen_8','Core i5-8265U'), ('Core i5','gen_8','Core i5-8300H'), ('Core i5','gen_8','Core i5-8350U'),
  ('Core i5','gen_9','Core i5-9300H'), ('Core i5','gen_9','Core i5-9400H'),
  ('Core i5','gen_10','Core i5-10210U'), ('Core i5','gen_10','Core i5-1035G1'), ('Core i5','gen_10','Core i5-1035G4'), ('Core i5','gen_10','Core i5-1035G7'), ('Core i5','gen_10','Core i5-10400H'),
  ('Core i5','gen_11','Core i5-1135G7'), ('Core i5','gen_11','Core i5-11400H'), ('Core i5','gen_11','Core i5-1155G7'),
  ('Core i5','gen_12','Core i5-1235U'), ('Core i5','gen_12','Core i5-1240P'), ('Core i5','gen_12','Core i5-12500H'), ('Core i5','gen_12','Core i5-12600H'),
  ('Core i5','gen_13','Core i5-1335U'), ('Core i5','gen_13','Core i5-1340P'), ('Core i5','gen_13','Core i5-13500H'),
  ('Core i5','gen_14','Core i5-14450HX'), ('Core i5','gen_14','Core i5-14500HX'),
  -- Core i7 mobile
  ('Core i7','gen_2','Core i7-2620M'), ('Core i7','gen_2','Core i7-2670QM'), ('Core i7','gen_2','Core i7-2720QM'),
  ('Core i7','gen_3','Core i7-3517U'), ('Core i7','gen_3','Core i7-3520M'), ('Core i7','gen_3','Core i7-3630QM'), ('Core i7','gen_3','Core i7-3720QM'),
  ('Core i7','gen_4','Core i7-4500U'), ('Core i7','gen_4','Core i7-4510U'), ('Core i7','gen_4','Core i7-4700HQ'), ('Core i7','gen_4','Core i7-4710HQ'),
  ('Core i7','gen_5','Core i7-5500U'), ('Core i7','gen_5','Core i7-5550U'), ('Core i7','gen_5','Core i7-5700HQ'),
  ('Core i7','gen_6','Core i7-6500U'), ('Core i7','gen_6','Core i7-6600U'), ('Core i7','gen_6','Core i7-6700HQ'), ('Core i7','gen_6','Core i7-6820HK'),
  ('Core i7','gen_7','Core i7-7500U'), ('Core i7','gen_7','Core i7-7600U'), ('Core i7','gen_7','Core i7-7700HQ'),
  ('Core i7','gen_8','Core i7-8550U'), ('Core i7','gen_8','Core i7-8565U'), ('Core i7','gen_8','Core i7-8750H'), ('Core i7','gen_8','Core i7-8850H'),
  ('Core i7','gen_9','Core i7-9750H'), ('Core i7','gen_9','Core i7-9850H'),
  ('Core i7','gen_10','Core i7-10510U'), ('Core i7','gen_10','Core i7-1065G7'), ('Core i7','gen_10','Core i7-10750H'), ('Core i7','gen_10','Core i7-10850H'),
  ('Core i7','gen_11','Core i7-1165G7'), ('Core i7','gen_11','Core i7-11800H'), ('Core i7','gen_11','Core i7-1195G7'), ('Core i7','gen_11','Core i7-11900H'),
  ('Core i7','gen_12','Core i7-1255U'), ('Core i7','gen_12','Core i7-1260P'), ('Core i7','gen_12','Core i7-12700H'), ('Core i7','gen_12','Core i7-12800H'),
  ('Core i7','gen_13','Core i7-1355U'), ('Core i7','gen_13','Core i7-1360P'), ('Core i7','gen_13','Core i7-13700H'), ('Core i7','gen_13','Core i7-13800H'),
  ('Core i7','gen_14','Core i7-14650HX'), ('Core i7','gen_14','Core i7-14700HX'),
  -- Core i9 mobile
  ('Core i9','gen_8','Core i9-8950HK'),
  ('Core i9','gen_9','Core i9-9880H'), ('Core i9','gen_9','Core i9-9980HK'),
  ('Core i9','gen_10','Core i9-10880H'), ('Core i9','gen_10','Core i9-10980HK'),
  ('Core i9','gen_11','Core i9-11900H'), ('Core i9','gen_11','Core i9-11950H'), ('Core i9','gen_11','Core i9-11980HK'),
  ('Core i9','gen_12','Core i9-12900H'), ('Core i9','gen_12','Core i9-12900HK'), ('Core i9','gen_12','Core i9-12950HX'),
  ('Core i9','gen_13','Core i9-13900H'), ('Core i9','gen_13','Core i9-13900HK'), ('Core i9','gen_13','Core i9-13950HX'), ('Core i9','gen_13','Core i9-13980HX'),
  ('Core i9','gen_14','Core i9-14900HX'), ('Core i9','gen_14','Core i9-14950HX'),
  -- Modern Core and Core Ultra laptop processors
  ('Core 3','series_1','Core 3 100U'), ('Core 5','series_1','Core 5 120U'), ('Core 7','series_1','Core 7 150U'),
  ('Core 5','series_2','Core 5 210H'), ('Core 5','series_2','Core 5 220H'), ('Core 7','series_2','Core 7 240H'), ('Core 7','series_2','Core 7 250H'),
  ('Core Ultra 5','series_1','Core Ultra 5 125H'), ('Core Ultra 5','series_1','Core Ultra 5 125U'), ('Core Ultra 5','series_1','Core Ultra 5 135H'), ('Core Ultra 5','series_1','Core Ultra 5 135U'),
  ('Core Ultra 5','series_2','Core Ultra 5 225H'), ('Core Ultra 5','series_2','Core Ultra 5 225U'), ('Core Ultra 5','series_2','Core Ultra 5 226V'), ('Core Ultra 5','series_2','Core Ultra 5 228V'),
  ('Core Ultra 7','series_1','Core Ultra 7 155H'), ('Core Ultra 7','series_1','Core Ultra 7 155U'), ('Core Ultra 7','series_1','Core Ultra 7 164U'), ('Core Ultra 7','series_1','Core Ultra 7 165H'), ('Core Ultra 7','series_1','Core Ultra 7 165U'),
  ('Core Ultra 7','series_2','Core Ultra 7 255H'), ('Core Ultra 7','series_2','Core Ultra 7 255U'), ('Core Ultra 7','series_2','Core Ultra 7 256V'), ('Core Ultra 7','series_2','Core Ultra 7 258V'), ('Core Ultra 7','series_2','Core Ultra 7 265H'), ('Core Ultra 7','series_2','Core Ultra 7 268V'),
  ('Core Ultra 9','series_1','Core Ultra 9 185H'),
  ('Core Ultra 9','series_2','Core Ultra 9 275HX'), ('Core Ultra 9','series_2','Core Ultra 9 285H'), ('Core Ultra 9','series_2','Core Ultra 9 285HX'), ('Core Ultra 9','series_2','Core Ultra 9 288V')
)
insert into public.processor_models (fk_familia_procesador_id, fk_processor_generation_id, nombre, alcance, fk_organizacion_id, activo)
select f.id, g.id, rm.nombre, 'GLOBAL', null, true
from requested_models rm
join public.processor_families f on f.nombre_normalizado = public.normalizar_nombre_catalogo(rm.family_name)
join public.processor_brands b on b.id = f.fk_marca_procesador_id and b.nombre_normalizado = public.normalizar_nombre_catalogo('Intel')
join public.processor_generations g on g.fk_processor_family_id = f.id and g.code = rm.generation_code
where not exists (
  select 1 from public.processor_models existing
  where existing.fk_familia_procesador_id = f.id
    and existing.fk_processor_generation_id = g.id
    and existing.fk_organizacion_id is null
    and existing.nombre_normalizado = public.normalizar_nombre_catalogo(rm.nombre)
);

-- The compatible-selector RPC exposes models only when this relation exists.
insert into public.processor_specifications (fk_processor_model_id, desktop_supported, notebook_supported)
select m.id, false, true
from public.processor_models m
join public.processor_families f on f.id = m.fk_familia_procesador_id
join public.processor_brands b on b.id = f.fk_marca_procesador_id
where b.nombre_normalizado = public.normalizar_nombre_catalogo('Intel')
  and m.fk_organizacion_id is null
  and f.nombre_normalizado in (
    public.normalizar_nombre_catalogo('Celeron'), public.normalizar_nombre_catalogo('Pentium'), public.normalizar_nombre_catalogo('Processor'),
    public.normalizar_nombre_catalogo('Core i3'), public.normalizar_nombre_catalogo('Core i5'), public.normalizar_nombre_catalogo('Core i7'), public.normalizar_nombre_catalogo('Core i9'),
    public.normalizar_nombre_catalogo('Core 3'), public.normalizar_nombre_catalogo('Core 5'), public.normalizar_nombre_catalogo('Core 7'),
    public.normalizar_nombre_catalogo('Core Ultra 5'), public.normalizar_nombre_catalogo('Core Ultra 7'), public.normalizar_nombre_catalogo('Core Ultra 9')
  )
on conflict (fk_processor_model_id) do update set notebook_supported = true;

commit;
