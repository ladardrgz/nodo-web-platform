-- AMD Ryzen 5 mobile models from the 5000 series.  Only catalogue identity
-- and Notebook compatibility are recorded; hardware specifications remain null.
begin;

with target_family as (
  select f.id as family_id, g.id as generation_id
  from public.processor_families f
  join public.processor_brands b on b.id = f.fk_marca_procesador_id
  join public.processor_generations g on g.fk_processor_family_id = f.id
  where b.nombre = 'AMD' and f.nombre = 'Ryzen 5' and g.code = '5000'
), model_names(nombre) as (values
  ('Ryzen 5 5500U'), ('Ryzen 5 5560U'), ('Ryzen 5 5600U'), ('Ryzen 5 5600H'),
  ('Ryzen 5 5600HS'), ('Ryzen 5 5625U'), ('Ryzen 5 5625C')
)
insert into public.processor_models (fk_familia_procesador_id, fk_processor_generation_id, nombre, alcance, fk_organizacion_id, activo)
select t.family_id, t.generation_id, n.nombre, 'GLOBAL', null, true
from target_family t cross join model_names n
where not exists (
  select 1 from public.processor_models m
  where m.fk_familia_procesador_id = t.family_id
    and m.fk_processor_generation_id = t.generation_id
    and m.fk_organizacion_id is null
    and m.nombre_normalizado = public.normalizar_nombre_catalogo(n.nombre)
);

insert into public.processor_specifications (fk_processor_model_id, desktop_supported, notebook_supported)
select m.id, false, true
from public.processor_models m
join public.processor_families f on f.id = m.fk_familia_procesador_id
join public.processor_brands b on b.id = f.fk_marca_procesador_id
join public.processor_generations g on g.id = m.fk_processor_generation_id
where b.nombre = 'AMD' and f.nombre = 'Ryzen 5' and g.code = '5000' and m.fk_organizacion_id is null
on conflict (fk_processor_model_id) do update set notebook_supported = true;

commit;
