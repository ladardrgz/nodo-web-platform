begin;

do $$
declare
  v_unresolved integer;
begin
  -- Every referenced legacy brand must have exactly one canonical natural-key match.
  select count(*) into v_unresolved
  from (
    select p.fk_gpu_chip_brand_id
    from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items l on l.id=p.fk_gpu_chip_brand_id and l.category='GPU_CHIP_BRAND'
    left join public.gpu_brands c
      on lower(c.code)=lower(l.code)
      or lower(regexp_replace(btrim(c.name),'\s+',' ','g'))=lower(regexp_replace(btrim(l.name),'\s+',' ','g'))
    where p.fk_gpu_chip_brand_id is not null
    group by p.fk_gpu_chip_brand_id
    having count(distinct c.id)<>1
  ) unresolved;
  if v_unresolved>0 then raise exception 'UNRESOLVED_OR_AMBIGUOUS_LEGACY_GPU_BRANDS: %',v_unresolved; end if;

  -- A family is only a match inside the canonical brand selected by the same profile.
  select count(*) into v_unresolved
  from (
    select p.fk_customer_device_id
    from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items lf on lf.id=p.fk_gpu_family_id and lf.category='GPU_FAMILY'
    left join public.hardware_catalog_items lb on lb.id=p.fk_gpu_chip_brand_id and lb.category='GPU_CHIP_BRAND'
    left join public.gpu_brands cb
      on lower(cb.code)=lower(lb.code)
      or lower(regexp_replace(btrim(cb.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lb.name),'\s+',' ','g'))
    left join public.gpu_families cf on cf.fk_gpu_brand_id=cb.id and (
      lower(cf.code)=lower(lf.code)
      or lower(regexp_replace(btrim(cf.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lf.name),'\s+',' ','g'))
    )
    where p.fk_gpu_family_id is not null
    group by p.fk_customer_device_id
    having count(distinct cf.id)<>1
  ) unresolved;
  if v_unresolved>0 then raise exception 'UNRESOLVED_OR_AMBIGUOUS_LEGACY_GPU_FAMILIES: %',v_unresolved; end if;

  -- A model is only a match inside the canonical family selected by the same profile.
  select count(*) into v_unresolved
  from (
    select p.fk_customer_device_id
    from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items lm on lm.id=p.fk_gpu_model_id and lm.category='GPU_MODEL'
    left join public.hardware_catalog_items lf on lf.id=p.fk_gpu_family_id and lf.category='GPU_FAMILY'
    left join public.hardware_catalog_items lb on lb.id=p.fk_gpu_chip_brand_id and lb.category='GPU_CHIP_BRAND'
    left join public.gpu_brands cb on lower(cb.code)=lower(lb.code) or lower(regexp_replace(btrim(cb.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lb.name),'\s+',' ','g'))
    left join public.gpu_families cf on cf.fk_gpu_brand_id=cb.id and (lower(cf.code)=lower(lf.code) or lower(regexp_replace(btrim(cf.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lf.name),'\s+',' ','g')))
    left join public.gpu_models cm on cm.fk_gpu_family_id=cf.id and (lower(cm.code)=lower(lm.code) or lower(regexp_replace(btrim(cm.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lm.name),'\s+',' ','g')))
    where p.fk_gpu_model_id is not null
    group by p.fk_customer_device_id
    having count(distinct cm.id)<>1
  ) unresolved;
  if v_unresolved>0 then raise exception 'UNRESOLVED_OR_AMBIGUOUS_LEGACY_GPU_MODELS: %',v_unresolved; end if;

  if exists(
    select 1 from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items l on l.id=p.fk_gpu_chip_brand_id
    join public.gpu_brands c on lower(c.code)=lower(l.code) or lower(regexp_replace(btrim(c.name),'\s+',' ','g'))=lower(regexp_replace(btrim(l.name),'\s+',' ','g'))
    where p.gpu_brand_id is not null and p.gpu_brand_id<>c.id
  ) then raise exception 'CONFLICTING_CANONICAL_GPU_BRAND'; end if;

  if exists(
    select 1 from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items lf on lf.id=p.fk_gpu_family_id and lf.category='GPU_FAMILY'
    join public.gpu_families cf on cf.fk_gpu_brand_id=p.gpu_brand_id and (lower(cf.code)=lower(lf.code) or lower(regexp_replace(btrim(cf.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lf.name),'\s+',' ','g')))
    where p.gpu_family_id is not null and p.gpu_family_id<>cf.id
  ) then raise exception 'CONFLICTING_CANONICAL_GPU_FAMILY'; end if;

  if exists(
    select 1 from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items lm on lm.id=p.fk_gpu_model_id and lm.category='GPU_MODEL'
    join public.gpu_models cm on cm.fk_gpu_family_id=p.gpu_family_id and (lower(cm.code)=lower(lm.code) or lower(regexp_replace(btrim(cm.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lm.name),'\s+',' ','g')))
    where p.gpu_model_id is not null and p.gpu_model_id<>cm.id
  ) then raise exception 'CONFLICTING_CANONICAL_GPU_MODEL'; end if;

  update public.customer_device_hardware_profiles p
  set gpu_brand_id=c.id
  from public.hardware_catalog_items l,public.gpu_brands c
  where l.id=p.fk_gpu_chip_brand_id and l.category='GPU_CHIP_BRAND'
    and (lower(c.code)=lower(l.code) or lower(regexp_replace(btrim(c.name),'\s+',' ','g'))=lower(regexp_replace(btrim(l.name),'\s+',' ','g')));

  update public.customer_device_hardware_profiles p
  set gpu_family_id=cf.id
  from public.hardware_catalog_items lf,public.gpu_families cf
  where lf.id=p.fk_gpu_family_id and lf.category='GPU_FAMILY'
    and cf.fk_gpu_brand_id=p.gpu_brand_id
    and (lower(cf.code)=lower(lf.code) or lower(regexp_replace(btrim(cf.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lf.name),'\s+',' ','g')))
    and (p.gpu_family_id is null or p.gpu_family_id=cf.id);

  update public.customer_device_hardware_profiles p
  set gpu_model_id=cm.id
  from public.hardware_catalog_items lm,public.gpu_models cm
  where lm.id=p.fk_gpu_model_id and lm.category='GPU_MODEL'
    and cm.fk_gpu_family_id=p.gpu_family_id
    and (lower(cm.code)=lower(lm.code) or lower(regexp_replace(btrim(cm.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lm.name),'\s+',' ','g')))
    and (p.gpu_model_id is null or p.gpu_model_id=cm.id);

  select count(*) into v_unresolved from public.customer_device_hardware_profiles
  where (fk_gpu_chip_brand_id is not null and gpu_brand_id is null)
     or (fk_gpu_family_id is not null and gpu_family_id is null)
     or (fk_gpu_model_id is not null and gpu_model_id is null);
  if v_unresolved>0 then raise exception 'LEGACY_GPU_REFERENCES_REMAIN: %',v_unresolved; end if;
  if exists(
    select 1 from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items lf on lf.id=p.fk_gpu_family_id
    join public.gpu_families cf on cf.fk_gpu_brand_id=p.gpu_brand_id and (lower(cf.code)=lower(lf.code) or lower(regexp_replace(btrim(cf.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lf.name),'\s+',' ','g')))
    where p.gpu_family_id<>cf.id
  ) then raise exception 'LEGACY_GPU_FAMILY_MIGRATION_MISMATCH'; end if;
  if exists(
    select 1 from public.customer_device_hardware_profiles p
    join public.hardware_catalog_items lm on lm.id=p.fk_gpu_model_id
    join public.gpu_models cm on cm.fk_gpu_family_id=p.gpu_family_id and (lower(cm.code)=lower(lm.code) or lower(regexp_replace(btrim(cm.name),'\s+',' ','g'))=lower(regexp_replace(btrim(lm.name),'\s+',' ','g')))
    where p.gpu_model_id<>cm.id
  ) then raise exception 'LEGACY_GPU_MODEL_MIGRATION_MISMATCH'; end if;
end $$;

alter table public.customer_device_hardware_profiles
  drop column fk_gpu_model_id,
  drop column fk_gpu_family_id,
  drop column fk_gpu_chip_brand_id,
  drop column fk_gpu_board_brand_id;

delete from public.hardware_catalog_items where category='GPU_MODEL';
delete from public.hardware_catalog_items where category='GPU_FAMILY';
delete from public.hardware_catalog_items where category='GPU_CHIP_BRAND';
delete from public.hardware_catalog_items where category='GPU_BOARD_BRAND';

alter table public.hardware_catalog_items drop constraint hardware_catalog_items_category_check;
alter table public.hardware_catalog_items add constraint hardware_catalog_items_category_check check (category in (
  'MOTHERBOARD_BRAND','MOTHERBOARD_SOCKET','MOTHERBOARD_FORM_FACTOR','MOTHERBOARD_CHIPSET',
  'PSU_BRAND','PSU_CERTIFICATION','DISPLAY_SIZE','DISPLAY_RESOLUTION',
  'DISPLAY_TECHNOLOGY','DISPLAY_REFRESH_RATE','CHARGER_CONNECTOR','OPERATING_SYSTEM',
  'PORT_CONNECTOR','PORT_PROTOCOL','WIFI_STANDARD','CONNECTIVITY','CHECKLIST_STATUS'
));

commit;
