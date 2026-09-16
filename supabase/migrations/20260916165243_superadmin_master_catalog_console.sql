-- Secure, domain-aware administration for the global device catalog.
-- No physical deletes are exposed. Historical rows remain addressable after
-- deactivation, while reception selectors continue to filter active rows.
begin;

-- Technical enrichment is optional during Notebook intake. Identity and the
-- operating system remain governed by their existing bindings.
update public.device_type_fields binding
set required = false
from public.device_types type, public.device_fields field
where binding.fk_tipo_dispositivo_id = type.id
  and binding.fk_campo_dispositivo_id = field.id
  and type.code = 'notebook'
  and field.key in (
    'processor_brand_id', 'processor_family_id', 'processor_generation_id',
    'processor_model_id', 'ram_modules', 'storage_drives',
    'gpu_brand_id', 'gpu_family_id', 'gpu_model_id',
    'motherboard_brand_id', 'motherboard_model_id'
  );

create or replace function public.assert_superadmin_catalog()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or public.current_app_role() <> 'SUPERADMIN' then
    raise exception 'FORBIDDEN';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = v_actor and role = 'SUPERADMIN' and status = 'ACTIVE'
  ) then
    raise exception 'FORBIDDEN';
  end if;
  return v_actor;
end;
$$;

revoke all on function public.assert_superadmin_catalog() from public, anon, authenticated;

create or replace function public.master_catalog_health(p_device_type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_type public.device_types;
declare v_result jsonb;
begin
  perform public.assert_superadmin_catalog();
  select * into v_type from public.device_types where id = p_device_type_id;
  if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;

  select jsonb_build_object(
    'type', jsonb_build_object('id', v_type.id, 'name', v_type.name, 'code', v_type.code),
    'counts', jsonb_build_object(
      'brands', (select count(*) from public.device_type_brands x join public.device_brands b on b.id=x.fk_marca_dispositivo_id where x.fk_tipo_dispositivo_id=v_type.id and b.is_active),
      'models', (select count(*) from public.device_models m where m.fk_tipo_dispositivo_id=v_type.id and m.is_active),
      'variants', (select count(*) from public.device_model_variants v join public.device_models m on m.id=v.fk_modelo_dispositivo_id where m.fk_tipo_dispositivo_id=v_type.id and v.is_active),
      'colors', (select count(*) from public.device_colors c where c.is_active),
      'processor_brands', (select count(distinct f.fk_marca_procesador_id) from public.processor_models m join public.processor_families f on f.id=m.fk_familia_procesador_id join public.processor_specifications s on s.fk_processor_model_id=m.id where m.activo and ((v_type.code='notebook' and s.notebook_supported) or (v_type.code='desktop_pc' and s.desktop_supported))),
      'processor_models', (select count(*) from public.processor_models m join public.processor_specifications s on s.fk_processor_model_id=m.id where m.activo and ((v_type.code='notebook' and s.notebook_supported) or (v_type.code='desktop_pc' and s.desktop_supported))),
      'gpu_brands', (select count(distinct f.fk_gpu_brand_id) from public.gpu_models m join public.gpu_families f on f.id=m.fk_gpu_family_id where m.is_active and ((v_type.code='notebook' and m.notebook_supported) or (v_type.code='desktop_pc' and m.desktop_supported))),
      'gpu_models', (select count(*) from public.gpu_models m where m.is_active and ((v_type.code='notebook' and m.notebook_supported) or (v_type.code='desktop_pc' and m.desktop_supported))),
      'motherboard_models', (select count(*) from public.motherboard_model_device_types x join public.motherboard_models m on m.id=x.motherboard_model_id where x.device_type_id=v_type.id and m.is_active),
      'checklist_controls', (select count(*) from public.device_type_reception_controls x join public.device_reception_controls c on c.id=x.fk_control_recepcion_dispositivo_id where x.fk_tipo_dispositivo_id=v_type.id and x.is_active and c.is_active)
    ),
    'warnings', coalesce((
      select jsonb_agg(w order by w->>'label') from (
        select jsonb_build_object('domain','GENERAL','kind','BRAND_WITHOUT_MODELS','label',b.name || ' no tiene modelos asociados a ' || v_type.name,'targetId',b.id) w
        from public.device_type_brands x join public.device_brands b on b.id=x.fk_marca_dispositivo_id
        where x.fk_tipo_dispositivo_id=v_type.id and b.is_active
          and not exists (select 1 from public.device_models m where m.fk_tipo_dispositivo_id=v_type.id and m.fk_marca_dispositivo_id=b.id and m.is_active)
        union all
        select jsonb_build_object('domain','CPU','kind','EMPTY_GENERATION','label',b.nombre || ' / ' || f.nombre || ' / ' || g.name || ' no tiene modelos compatibles con ' || v_type.name,'targetId',g.id)
        from public.processor_generations g join public.processor_families f on f.id=g.fk_processor_family_id join public.processor_brands b on b.id=f.fk_marca_procesador_id
        where g.is_active and f.activo and b.activo and v_type.code in ('notebook','desktop_pc')
          and not exists (select 1 from public.processor_models m join public.processor_specifications s on s.fk_processor_model_id=m.id where m.fk_processor_generation_id=g.id and m.activo and ((v_type.code='notebook' and s.notebook_supported) or (v_type.code='desktop_pc' and s.desktop_supported)))
        union all
        select jsonb_build_object('domain','GPU','kind','EMPTY_FAMILY','label',b.name || ' / ' || f.name || ' no tiene modelos compatibles con ' || v_type.name,'targetId',f.id)
        from public.gpu_families f join public.gpu_brands b on b.id=f.fk_gpu_brand_id
        where f.is_active and b.is_active and v_type.code in ('notebook','desktop_pc')
          and not exists (select 1 from public.gpu_models m where m.fk_gpu_family_id=f.id and m.is_active and ((v_type.code='notebook' and m.notebook_supported) or (v_type.code='desktop_pc' and m.desktop_supported)))
        union all
        select jsonb_build_object('domain','MOTHERBOARD','kind','ORPHAN_MODEL','label',mf.name || ' / ' || mm.name || ' no tiene tipo compatible','targetId',mm.id)
        from public.motherboard_models mm join public.motherboard_manufacturers mf on mf.id=mm.motherboard_manufacturer_id
        where mm.is_active and not exists (select 1 from public.motherboard_model_device_types x where x.motherboard_model_id=mm.id)
      ) warnings
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.superadmin_create_device_brand(p_name text, p_device_type_ids uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid := public.assert_superadmin_catalog(); v_id uuid; v_name text := regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  if char_length(v_name) not between 2 and 80 or coalesce(cardinality(p_device_type_ids),0)=0 then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if exists(select 1 from unnest(p_device_type_ids) x(id) left join public.device_types t on t.id=x.id where t.id is null) then raise exception 'INVALID_DEVICE_TYPE'; end if;
  insert into public.device_brands(name,alcance,fk_organizacion_id,is_active,created_by)
  values(v_name,'GLOBAL',null,true,v_actor)
  on conflict on constraint uq_marcas_dispositivo_nombre_alcance do update set is_active=true,updated_at=now()
  returning id into v_id;
  insert into public.device_type_brands(fk_tipo_dispositivo_id,fk_marca_dispositivo_id) select distinct id,v_id from unnest(p_device_type_ids) x(id) on conflict do nothing;
  return v_id;
end $$;

create or replace function public.superadmin_create_device_model(p_device_type_id uuid,p_brand_id uuid,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid := public.assert_superadmin_catalog(); v_id uuid; v_name text := regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  if not exists(select 1 from public.device_type_brands where fk_tipo_dispositivo_id=p_device_type_id and fk_marca_dispositivo_id=p_brand_id) then raise exception 'BRAND_NOT_ALLOWED_FOR_TYPE'; end if;
  insert into public.device_models(fk_tipo_dispositivo_id,fk_marca_dispositivo_id,name,alcance,fk_organizacion_id,is_active,created_by)
  values(p_device_type_id,p_brand_id,v_name,'GLOBAL',null,true,v_actor)
  on conflict on constraint uq_modelos_dispositivo_nombre_alcance do update set is_active=true,updated_at=now()
  returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_device_variant(p_model_id uuid,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid := public.assert_superadmin_catalog(); v_id uuid; v_name text := regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  insert into public.device_model_variants(fk_modelo_dispositivo_id,name,is_active,created_by)
  values(p_model_id,v_name,true,v_actor)
  on conflict on constraint uq_variantes_modelo_dispositivo_nombre do update set is_active=true,updated_at=now()
  returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_processor_model(p_brand_id uuid,p_family_id uuid,p_generation_id uuid,p_name text,p_notebook boolean,p_desktop boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid := public.assert_superadmin_catalog(); v_id uuid; v_name text := regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  if not p_notebook and not p_desktop then raise exception 'PROCESSOR_REQUIRES_COMPATIBILITY'; end if;
  if not exists(select 1 from public.processor_families where id=p_family_id and fk_marca_procesador_id=p_brand_id and activo) then raise exception 'INVALID_PROCESSOR_FAMILY'; end if;
  if not exists(select 1 from public.processor_generations where id=p_generation_id and fk_processor_family_id=p_family_id and is_active) then raise exception 'INVALID_PROCESSOR_GENERATION'; end if;
  insert into public.processor_models(fk_familia_procesador_id,fk_processor_generation_id,nombre,alcance,fk_organizacion_id,activo,created_by)
  values(p_family_id,p_generation_id,v_name,'GLOBAL',null,true,v_actor)
  on conflict on constraint uq_modelos_procesador_nombre_alcance do update set activo=true,updated_at=now()
  returning id into v_id;
  insert into public.processor_specifications(fk_processor_model_id,desktop_supported,notebook_supported)
  values(v_id,p_desktop,p_notebook)
  on conflict(fk_processor_model_id) do update set desktop_supported=excluded.desktop_supported,notebook_supported=excluded.notebook_supported,updated_at=now();
  return v_id;
end $$;

create or replace function public.superadmin_create_gpu_brand(p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g'); v_code text;
begin
  perform public.assert_superadmin_catalog(); v_code:=trim(both '_' from regexp_replace(public.normalizar_nombre_catalogo(v_name),'[^a-z0-9]+','_','g'));
  insert into public.gpu_brands(code,name,is_active) values(v_code,v_name,true)
  on conflict(code) do update set name=excluded.name,is_active=true,updated_at=now() returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_gpu_family(p_brand_id uuid,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g'); v_code text;
begin
  perform public.assert_superadmin_catalog(); if not exists(select 1 from public.gpu_brands where id=p_brand_id and is_active) then raise exception 'INVALID_GPU_BRAND'; end if;
  v_code:=trim(both '_' from regexp_replace(public.normalizar_nombre_catalogo(v_name),'[^a-z0-9]+','_','g'));
  insert into public.gpu_families(fk_gpu_brand_id,code,name,is_active) values(p_brand_id,v_code,v_name,true)
  on conflict(fk_gpu_brand_id,code) do update set name=excluded.name,is_active=true,updated_at=now() returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_gpu_model(p_family_id uuid,p_name text,p_graphics_kind text,p_notebook boolean,p_desktop boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g'); v_code text;
begin
  perform public.assert_superadmin_catalog();
  if p_graphics_kind not in ('INTEGRATED','DEDICATED') or (not p_notebook and not p_desktop) then raise exception 'INVALID_GPU_MODEL'; end if;
  if not exists(select 1 from public.gpu_families where id=p_family_id and is_active) then raise exception 'INVALID_GPU_FAMILY'; end if;
  v_code:=trim(both '_' from regexp_replace(public.normalizar_nombre_catalogo(v_name),'[^a-z0-9]+','_','g'));
  insert into public.gpu_models(fk_gpu_family_id,code,name,graphics_kind,desktop_supported,notebook_supported,is_active)
  values(p_family_id,v_code,v_name,p_graphics_kind,p_desktop,p_notebook,true)
  on conflict(fk_gpu_family_id,code) do update set name=excluded.name,graphics_kind=excluded.graphics_kind,desktop_supported=excluded.desktop_supported,notebook_supported=excluded.notebook_supported,is_active=true,updated_at=now()
  returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_motherboard_manufacturer(p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=public.assert_superadmin_catalog(); v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  insert into public.motherboard_manufacturers(name,alcance,fk_organizacion_id,is_active,created_by) values(v_name,'GLOBAL',null,true,v_actor)
  on conflict on constraint uq_motherboard_manufacturers_name_scope do update set is_active=true,updated_at=now() returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_motherboard_model(p_manufacturer_id uuid,p_name text,p_device_type_ids uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=public.assert_superadmin_catalog(); v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  if coalesce(cardinality(p_device_type_ids),0)=0 then raise exception 'MOTHERBOARD_REQUIRES_COMPATIBILITY'; end if;
  insert into public.motherboard_models(motherboard_manufacturer_id,name,alcance,fk_organizacion_id,is_active,created_by) values(p_manufacturer_id,v_name,'GLOBAL',null,true,v_actor)
  on conflict on constraint uq_motherboard_models_name_scope do update set is_active=true,updated_at=now() returning id into v_id;
  insert into public.motherboard_model_device_types(motherboard_model_id,device_type_id) select distinct v_id,id from unnest(p_device_type_ids) x(id) on conflict do nothing;
  return v_id;
end $$;

create or replace function public.superadmin_create_device_color(p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=public.assert_superadmin_catalog(); v_id uuid; v_name text:=regexp_replace(btrim(coalesce(p_name,'')),'\s+',' ','g');
begin
  insert into public.device_colors(name,alcance,fk_organizacion_id,is_active,created_by) values(v_name,'GLOBAL',null,true,v_actor)
  on conflict on constraint uq_colores_dispositivo_nombre_alcance do update set is_active=true,updated_at=now() returning id into v_id; return v_id;
end $$;

create or replace function public.superadmin_create_ram_type(p_code text,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin perform public.assert_superadmin_catalog(); insert into public.ram_types(code,name,is_active) values(lower(btrim(p_code)),btrim(p_name),true) on conflict(code) do update set name=excluded.name,is_active=true returning id into v_id; return v_id; end $$;

create or replace function public.superadmin_create_ram_speed(p_ram_type_id uuid,p_mhz integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin perform public.assert_superadmin_catalog(); insert into public.ram_speeds(fk_ram_type_id,mhz,is_active) values(p_ram_type_id,p_mhz,true) on conflict(fk_ram_type_id,mhz) do update set is_active=true returning id into v_id; return v_id; end $$;

create or replace function public.superadmin_create_storage_option(p_entity text,p_code text,p_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  perform public.assert_superadmin_catalog();
  if p_entity='storage_interface' then insert into public.storage_interfaces(code,name,is_active) values(lower(btrim(p_code)),btrim(p_name),true) on conflict(code) do update set name=excluded.name,is_active=true returning id into v_id;
  elsif p_entity='storage_form_factor' then insert into public.storage_form_factors(code,name,is_active) values(lower(btrim(p_code)),btrim(p_name),true) on conflict(code) do update set name=excluded.name,is_active=true returning id into v_id;
  else raise exception 'INVALID_STORAGE_ENTITY'; end if;
  return v_id;
end $$;

create or replace function public.superadmin_create_reception_control(p_key text,p_label text,p_description text,p_critical boolean,p_device_type_ids uuid[])
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  perform public.assert_superadmin_catalog();
  insert into public.device_reception_controls(key,label,descripcion,is_active,is_critical) values(lower(btrim(p_key)),btrim(p_label),nullif(btrim(p_description),''),true,p_critical)
  on conflict(key) do update set label=excluded.label,descripcion=excluded.descripcion,is_active=true,is_critical=excluded.is_critical,updated_at=now() returning id into v_id;
  insert into public.device_type_reception_controls(fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id,sort_order,obligatorio,is_active)
  select x.device_type_id,v_id,coalesce((select max(c.sort_order)+10 from public.device_type_reception_controls c where c.fk_tipo_dispositivo_id=x.device_type_id),10),false,true
  from unnest(p_device_type_ids) x(device_type_id)
  on conflict(fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id) do update set is_active=true;
  return v_id;
end $$;

create or replace function public.superadmin_set_catalog_active(p_entity text,p_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform public.assert_superadmin_catalog();
  case p_entity
    when 'device_brand' then update public.device_brands set is_active=p_active,updated_at=now() where id=p_id and alcance='GLOBAL';
    when 'device_model' then update public.device_models set is_active=p_active,updated_at=now() where id=p_id and alcance='GLOBAL';
    when 'device_variant' then update public.device_model_variants set is_active=p_active,updated_at=now() where id=p_id;
    when 'device_color' then update public.device_colors set is_active=p_active,updated_at=now() where id=p_id and alcance='GLOBAL';
    when 'processor_model' then update public.processor_models set activo=p_active,updated_at=now() where id=p_id and alcance='GLOBAL';
    when 'gpu_brand' then update public.gpu_brands set is_active=p_active,updated_at=now() where id=p_id;
    when 'gpu_family' then update public.gpu_families set is_active=p_active,updated_at=now() where id=p_id;
    when 'gpu_model' then update public.gpu_models set is_active=p_active,updated_at=now() where id=p_id;
    when 'motherboard_manufacturer' then update public.motherboard_manufacturers set is_active=p_active,updated_at=now() where id=p_id and alcance='GLOBAL';
    when 'motherboard_model' then update public.motherboard_models set is_active=p_active,updated_at=now() where id=p_id and alcance='GLOBAL';
    when 'ram_type' then update public.ram_types set is_active=p_active where id=p_id;
    when 'ram_speed' then update public.ram_speeds set is_active=p_active where id=p_id;
    when 'storage_interface' then update public.storage_interfaces set is_active=p_active where id=p_id;
    when 'storage_form_factor' then update public.storage_form_factors set is_active=p_active where id=p_id;
    when 'reception_control' then update public.device_reception_controls set is_active=p_active,updated_at=now() where id=p_id;
    else raise exception 'INVALID_CATALOG_ENTITY';
  end case;
  if not found then raise exception 'CATALOG_ITEM_NOT_FOUND'; end if;
end $$;

revoke all on function public.master_catalog_health(uuid) from public,anon;
revoke all on function public.superadmin_create_device_brand(text,uuid[]) from public,anon;
revoke all on function public.superadmin_create_device_model(uuid,uuid,text) from public,anon;
revoke all on function public.superadmin_create_device_variant(uuid,text) from public,anon;
revoke all on function public.superadmin_create_processor_model(uuid,uuid,uuid,text,boolean,boolean) from public,anon;
revoke all on function public.superadmin_create_gpu_brand(text) from public,anon;
revoke all on function public.superadmin_create_gpu_family(uuid,text) from public,anon;
revoke all on function public.superadmin_create_gpu_model(uuid,text,text,boolean,boolean) from public,anon;
revoke all on function public.superadmin_create_motherboard_manufacturer(text) from public,anon;
revoke all on function public.superadmin_create_motherboard_model(uuid,text,uuid[]) from public,anon;
revoke all on function public.superadmin_create_device_color(text) from public,anon;
revoke all on function public.superadmin_create_ram_type(text,text) from public,anon;
revoke all on function public.superadmin_create_ram_speed(uuid,integer) from public,anon;
revoke all on function public.superadmin_create_storage_option(text,text,text) from public,anon;
revoke all on function public.superadmin_create_reception_control(text,text,text,boolean,uuid[]) from public,anon;
revoke all on function public.superadmin_set_catalog_active(text,uuid,boolean) from public,anon;

grant execute on function public.master_catalog_health(uuid) to authenticated;
grant execute on function public.superadmin_create_device_brand(text,uuid[]) to authenticated;
grant execute on function public.superadmin_create_device_model(uuid,uuid,text) to authenticated;
grant execute on function public.superadmin_create_device_variant(uuid,text) to authenticated;
grant execute on function public.superadmin_create_processor_model(uuid,uuid,uuid,text,boolean,boolean) to authenticated;
grant execute on function public.superadmin_create_gpu_brand(text) to authenticated;
grant execute on function public.superadmin_create_gpu_family(uuid,text) to authenticated;
grant execute on function public.superadmin_create_gpu_model(uuid,text,text,boolean,boolean) to authenticated;
grant execute on function public.superadmin_create_motherboard_manufacturer(text) to authenticated;
grant execute on function public.superadmin_create_motherboard_model(uuid,text,uuid[]) to authenticated;
grant execute on function public.superadmin_create_device_color(text) to authenticated;
grant execute on function public.superadmin_create_ram_type(text,text) to authenticated;
grant execute on function public.superadmin_create_ram_speed(uuid,integer) to authenticated;
grant execute on function public.superadmin_create_storage_option(text,text,text) to authenticated;
grant execute on function public.superadmin_create_reception_control(text,text,text,boolean,uuid[]) to authenticated;
grant execute on function public.superadmin_set_catalog_active(text,uuid,boolean) to authenticated;

commit;
