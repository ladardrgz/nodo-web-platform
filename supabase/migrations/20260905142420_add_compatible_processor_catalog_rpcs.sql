begin;

create or replace function public.get_compatible_processor_brands(p_device_type_code text)
returns table(id uuid,name text,parent_id uuid,secondary_parent_id uuid,organization_id uuid)
language sql stable security invoker set search_path='' as $$
  select distinct b.id,b.nombre,null::uuid,null::uuid,null::uuid
  from public.processor_brands b
  where b.activo and p_device_type_code in ('desktop_pc','notebook') and exists (
    select 1 from public.processor_families f
    join public.processor_models m on m.fk_familia_procesador_id=f.id and m.activo
    join public.processor_specifications s on s.fk_processor_model_id=m.id
    where f.fk_marca_procesador_id=b.id and f.activo
      and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())
      and ((p_device_type_code='desktop_pc' and s.desktop_supported) or (p_device_type_code='notebook' and s.notebook_supported))
  ) order by b.nombre;
$$;

create or replace function public.get_compatible_processor_families(p_device_type_code text,p_brand_id uuid)
returns table(id uuid,name text,parent_id uuid,secondary_parent_id uuid,organization_id uuid)
language sql stable security invoker set search_path='' as $$
  select f.id,f.nombre,f.fk_marca_procesador_id,null::uuid,null::uuid
  from public.processor_families f join public.processor_brands b on b.id=f.fk_marca_procesador_id and b.activo
  where f.activo and f.fk_marca_procesador_id=p_brand_id and p_device_type_code in ('desktop_pc','notebook') and exists (
    select 1 from public.processor_models m join public.processor_specifications s on s.fk_processor_model_id=m.id
    where m.fk_familia_procesador_id=f.id and m.activo
      and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())
      and ((p_device_type_code='desktop_pc' and s.desktop_supported) or (p_device_type_code='notebook' and s.notebook_supported))
  ) order by f.nombre_normalizado,f.id;
$$;

create or replace function public.get_compatible_processor_generations(p_device_type_code text,p_brand_id uuid,p_family_id uuid)
returns table(id uuid,name text,parent_id uuid,secondary_parent_id uuid,organization_id uuid)
language sql stable security invoker set search_path='' as $$
  select g.id,g.name,g.fk_processor_family_id,null::uuid,null::uuid
  from public.processor_generations g
  join public.processor_families f on f.id=g.fk_processor_family_id and f.activo and f.fk_marca_procesador_id=p_brand_id
  join public.processor_brands b on b.id=f.fk_marca_procesador_id and b.activo
  where g.is_active and g.fk_processor_family_id=p_family_id and p_device_type_code in ('desktop_pc','notebook') and exists (
    select 1 from public.processor_models m join public.processor_specifications s on s.fk_processor_model_id=m.id
    where m.fk_familia_procesador_id=f.id and m.fk_processor_generation_id=g.id and m.activo
      and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())
      and ((p_device_type_code='desktop_pc' and s.desktop_supported) or (p_device_type_code='notebook' and s.notebook_supported))
  ) order by g.sort_order,g.name,g.id;
$$;

create or replace function public.get_compatible_processor_models(p_device_type_code text,p_family_id uuid,p_generation_id uuid)
returns table(id uuid,name text,parent_id uuid,secondary_parent_id uuid,organization_id uuid)
language sql stable security invoker set search_path='' as $$
  select m.id,m.nombre,m.fk_familia_procesador_id,m.fk_processor_generation_id,m.fk_organizacion_id
  from public.processor_models m
  join public.processor_families f on f.id=m.fk_familia_procesador_id and f.activo
  join public.processor_brands b on b.id=f.fk_marca_procesador_id and b.activo
  join public.processor_generations g on g.id=m.fk_processor_generation_id and g.is_active and g.fk_processor_family_id=f.id
  join public.processor_specifications s on s.fk_processor_model_id=m.id
  where m.activo and m.fk_familia_procesador_id=p_family_id and m.fk_processor_generation_id=p_generation_id
    and p_device_type_code in ('desktop_pc','notebook')
    and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())
    and ((p_device_type_code='desktop_pc' and s.desktop_supported) or (p_device_type_code='notebook' and s.notebook_supported))
  order by m.nombre_normalizado,m.id;
$$;

revoke all on function public.get_compatible_processor_brands(text) from public,anon;
revoke all on function public.get_compatible_processor_families(text,uuid) from public,anon;
revoke all on function public.get_compatible_processor_generations(text,uuid,uuid) from public,anon;
revoke all on function public.get_compatible_processor_models(text,uuid,uuid) from public,anon;
grant execute on function public.get_compatible_processor_brands(text) to authenticated;
grant execute on function public.get_compatible_processor_families(text,uuid) to authenticated;
grant execute on function public.get_compatible_processor_generations(text,uuid,uuid) to authenticated;
grant execute on function public.get_compatible_processor_models(text,uuid,uuid) to authenticated;

commit;
