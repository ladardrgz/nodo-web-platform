
  create table "public"."gpu_brands" (
    "id" uuid not null default gen_random_uuid(),
    "code" text not null,
    "name" text not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."gpu_brands" enable row level security;


  create table "public"."gpu_families" (
    "id" uuid not null default gen_random_uuid(),
    "fk_gpu_brand_id" uuid not null,
    "code" text not null,
    "name" text not null,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."gpu_families" enable row level security;


  create table "public"."gpu_models" (
    "id" uuid not null default gen_random_uuid(),
    "fk_gpu_family_id" uuid not null,
    "code" text not null,
    "name" text not null,
    "graphics_kind" text not null,
    "desktop_supported" boolean not null default false,
    "notebook_supported" boolean not null default false,
    "is_active" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."gpu_models" enable row level security;

CREATE UNIQUE INDEX gpu_brands_code_key ON public.gpu_brands USING btree (code);

CREATE UNIQUE INDEX gpu_brands_name_key ON public.gpu_brands USING btree (name);

CREATE UNIQUE INDEX gpu_brands_pkey ON public.gpu_brands USING btree (id);

CREATE INDEX gpu_families_brand_idx ON public.gpu_families USING btree (fk_gpu_brand_id);

CREATE UNIQUE INDEX gpu_families_fk_gpu_brand_id_code_key ON public.gpu_families USING btree (fk_gpu_brand_id, code);

CREATE UNIQUE INDEX gpu_families_pkey ON public.gpu_families USING btree (id);

CREATE INDEX gpu_models_family_idx ON public.gpu_models USING btree (fk_gpu_family_id);

CREATE UNIQUE INDEX gpu_models_fk_gpu_family_id_code_key ON public.gpu_models USING btree (fk_gpu_family_id, code);

CREATE UNIQUE INDEX gpu_models_pkey ON public.gpu_models USING btree (id);

alter table "public"."gpu_brands" add constraint "gpu_brands_pkey" PRIMARY KEY using index "gpu_brands_pkey";

alter table "public"."gpu_families" add constraint "gpu_families_pkey" PRIMARY KEY using index "gpu_families_pkey";

alter table "public"."gpu_models" add constraint "gpu_models_pkey" PRIMARY KEY using index "gpu_models_pkey";

alter table "public"."gpu_brands" add constraint "gpu_brands_code_key" UNIQUE using index "gpu_brands_code_key";

alter table "public"."gpu_brands" add constraint "gpu_brands_name_key" UNIQUE using index "gpu_brands_name_key";

alter table "public"."gpu_families" add constraint "gpu_families_fk_gpu_brand_id_code_key" UNIQUE using index "gpu_families_fk_gpu_brand_id_code_key";

alter table "public"."gpu_families" add constraint "gpu_families_fk_gpu_brand_id_fkey" FOREIGN KEY (fk_gpu_brand_id) REFERENCES public.gpu_brands(id) ON DELETE RESTRICT not valid;

alter table "public"."gpu_families" validate constraint "gpu_families_fk_gpu_brand_id_fkey";

alter table "public"."gpu_models" add constraint "gpu_models_fk_gpu_family_id_code_key" UNIQUE using index "gpu_models_fk_gpu_family_id_code_key";

alter table "public"."gpu_models" add constraint "gpu_models_fk_gpu_family_id_fkey" FOREIGN KEY (fk_gpu_family_id) REFERENCES public.gpu_families(id) ON DELETE RESTRICT not valid;

alter table "public"."gpu_models" validate constraint "gpu_models_fk_gpu_family_id_fkey";

alter table "public"."gpu_models" add constraint "gpu_models_graphics_kind_check" CHECK ((graphics_kind = ANY (ARRAY['INTEGRATED'::text, 'DEDICATED'::text]))) not valid;

alter table "public"."gpu_models" validate constraint "gpu_models_graphics_kind_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.admin_create_organization(name text, slug text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_name text := regexp_replace(trim(name), '[[:space:]]+', ' ', 'g');
  v_slug text := lower(trim(slug));
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if char_length(v_name) not between 2 and 120 or v_name !~ '^[[:alnum:]_ -]+$' then raise exception 'Invalid organization name'; end if;
  if char_length(v_slug) not between 2 and 80 or v_slug !~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$' then raise exception 'Invalid organization identifier'; end if;
  insert into public.organizations (name, slug) values (v_name, v_slug) returning id into v_id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_id, auth.uid(), 'ORGANIZATION_CREATED', 'ORGANIZATION', v_id, jsonb_build_object('after', jsonb_build_object('name', v_name, 'slug', v_slug, 'status', 'ACTIVE')));
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_log_organization_event(p_organization_id uuid, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_set_organization_status(p_organization_id uuid, p_status public.organization_status, p_confirmation text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.organizations%rowtype;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  select * into v_old from public.organizations where id = p_organization_id for update;
  if not found then raise exception 'Organization not found'; end if;
  if v_old.status = p_status then return; end if;
  if p_status = 'SUSPENDED' and p_confirmation <> 'SUSPENDER' then raise exception 'Invalid confirmation'; end if;
  update public.organizations set status = p_status where id = p_organization_id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), case when p_status = 'SUSPENDED' then 'ORGANIZATION_SUSPENDED' else 'ORGANIZATION_REACTIVATED' end, 'ORGANIZATION', p_organization_id, jsonb_build_object('before', jsonb_build_object('status', v_old.status), 'after', jsonb_build_object('status', p_status)));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_update_profile_access(p_user_id uuid, p_role public.app_role, p_status public.profile_status, p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old public.profiles%rowtype;
  v_active_superadmins integer;
  v_organization_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  perform pg_advisory_xact_lock(hashtextextended('nodo_active_superadmin_invariant', 0));
  select * into v_old from public.profiles where id = p_user_id for update;
  if not found then raise exception 'Profile not found'; end if;

  if v_old.role = 'SUPERADMIN' and v_old.status = 'ACTIVE' and (p_role <> 'SUPERADMIN' or p_status <> 'ACTIVE') then
    select count(*) into v_active_superadmins from public.profiles where role = 'SUPERADMIN' and status = 'ACTIVE';
    if v_active_superadmins <= 1 then raise exception 'LAST_ACTIVE_SUPERADMIN'; end if;
  end if;

  if p_role = 'SUPERADMIN' then
    v_organization_id := null;
  else
    if p_organization_id is null then raise exception 'Organization required'; end if;
    perform 1 from public.organizations where id = p_organization_id;
    if not found then raise exception 'Organization not found'; end if;
    v_organization_id := p_organization_id;
  end if;

  update public.profiles set role = p_role, status = p_status, organization_id = v_organization_id where id = p_user_id;
  if v_old.role is distinct from p_role then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_organization_id, auth.uid(), 'USER_ROLE_CHANGED', 'PROFILE', p_user_id, jsonb_build_object('before', jsonb_build_object('role', v_old.role), 'after', jsonb_build_object('role', p_role)));
  end if;
  if v_old.status is distinct from p_status then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_organization_id, auth.uid(), 'USER_STATUS_CHANGED', 'PROFILE', p_user_id, jsonb_build_object('before', jsonb_build_object('status', v_old.status), 'after', jsonb_build_object('status', p_status)));
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.assert_reception_owner()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_org uuid;
begin
 select p.organization_id into v_org from public.profiles p join public.organizations o on o.id=p.organization_id where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and o.status='ACTIVE' and o.initial_setup_completed;
 if v_org is null then raise exception 'FORBIDDEN'; end if; return v_org;
end; $function$
;

CREATE OR REPLACE FUNCTION public.audit_profile_data_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.first_name is distinct from new.first_name or old.last_name is distinct from new.last_name or old.display_name is distinct from new.display_name then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (new.organization_id, auth.uid(), 'PROFILE_UPDATED', 'PROFILE', new.id, jsonb_build_object('personal_data', true));
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.complete_initial_organization_setup(p_name text, p_trade_name text, p_logo_path text, p_phone text, p_contact_email text, p_address text, p_locality text, p_province text, p_description text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid := public.current_organization_id();
  v_logo_path text := nullif(trim(p_logo_path), '');
begin
  if auth.uid() is null or public.current_app_role() <> 'OWNER' then
    raise exception 'Forbidden';
  end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;
  if char_length(trim(p_name)) not between 2 and 120 then raise exception 'Invalid organization name'; end if;
  if char_length(trim(p_trade_name)) not between 2 and 120 then raise exception 'Invalid trade name'; end if;
  if char_length(trim(p_phone)) not between 6 and 30 then raise exception 'Invalid phone'; end if;
  if trim(p_contact_email) !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email'; end if;
  if char_length(trim(p_address)) not between 3 and 180 then raise exception 'Invalid address'; end if;
  if char_length(trim(p_locality)) not between 2 and 100 then raise exception 'Invalid locality'; end if;
  if char_length(trim(p_province)) not between 2 and 100 then raise exception 'Invalid province'; end if;
  if char_length(trim(p_description)) not between 10 and 600 then raise exception 'Invalid description'; end if;
  if v_logo_path is not null and (
    v_logo_path not like v_organization_id::text || '/%'
    or v_logo_path like '%..%'
  ) then raise exception 'Invalid logo path'; end if;

  update public.organizations
  set
    name = trim(p_name),
    trade_name = trim(p_trade_name),
    logo_path = v_logo_path,
    phone = trim(p_phone),
    contact_email = lower(trim(p_contact_email)),
    address = trim(p_address),
    locality = trim(p_locality),
    province = trim(p_province),
    description = trim(p_description),
    initial_setup_completed = true
  where id = v_organization_id and status = 'ACTIVE';

  if not found then raise exception 'Organization not available'; end if;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization_id, auth.uid(), 'ORGANIZATION_SETUP_COMPLETED', 'ORGANIZATION', v_organization_id, '{}');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.complete_password_change()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set must_change_password = false where id = auth.uid();
end;
$function$
;

CREATE OR REPLACE FUNCTION public.confirm_device_reception(p_customer_id uuid, p_device_id uuid, p_reported_problem text, p_observations text, p_inspection jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'RECEPTION_CONFIRMED','DEVICE_RECEPTION',v_id,jsonb_build_object('device_id',p_device_id,'condition',v_condition)); return v_id; end; $function$
;

CREATE OR REPLACE FUNCTION public.consume_auth_rate_limit(p_action text, p_key_hash text)
 RETURNS TABLE(allowed boolean, retry_after_seconds integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_max integer;
  v_window interval;
  v_block interval;
  v_row public.auth_rate_limits%rowtype;
begin
  case upper(p_action)
    when 'LOGIN' then v_max := 5; v_window := interval '15 minutes'; v_block := interval '15 minutes';
    when 'REGISTER' then v_max := 3; v_window := interval '1 hour'; v_block := interval '1 hour';
    when 'PASSWORD_RESET' then v_max := 3; v_window := interval '1 hour'; v_block := interval '1 hour';
    when 'RESEND_VERIFICATION' then v_max := 3; v_window := interval '1 hour'; v_block := interval '1 hour';
    when 'OAUTH' then v_max := 20; v_window := interval '15 minutes'; v_block := interval '15 minutes';
    when 'ADMIN_MUTATION' then v_max := 60; v_window := interval '15 minutes'; v_block := interval '15 minutes';
    else raise exception 'Unsupported rate-limit action';
  end case;
  if p_key_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid key hash'; end if;
  insert into public.auth_rate_limits (action, key_hash, attempts, window_started_at, updated_at)
  values (upper(p_action), p_key_hash, 0, v_now, v_now) on conflict do nothing;
  select * into v_row from public.auth_rate_limits where action = upper(p_action) and key_hash = p_key_hash for update;
  if v_row.blocked_until is not null and v_row.blocked_until > v_now then
    return query select false, greatest(1, ceil(extract(epoch from (v_row.blocked_until - v_now)))::integer); return;
  end if;
  if v_row.window_started_at + v_window <= v_now then
    update public.auth_rate_limits set attempts = 1, window_started_at = v_now, blocked_until = null, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
    return query select true, 0; return;
  end if;
  if v_row.attempts >= v_max then
    update public.auth_rate_limits set blocked_until = v_now + v_block, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
    return query select false, ceil(extract(epoch from v_block))::integer; return;
  end if;
  update public.auth_rate_limits set attempts = attempts + 1, updated_at = v_now where action = upper(p_action) and key_hash = p_key_hash;
  return query select true, 0;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.create_customer_device(p_customer_id uuid, p_type_id uuid, p_brand_id uuid, p_model text, p_year text, p_color text, p_serial_number text, p_imei_1 text, p_imei_2 text, p_attributes jsonb, p_memories jsonb, p_storage_units jsonb, p_accessories text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin
 perform 1 from public.customers where id=p_customer_id and organization_id=v_org; if not found then raise exception 'INVALID_CUSTOMER'; end if;
 perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
 perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
 insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
 values(v_org,p_customer_id,p_type_id,p_brand_id,regexp_replace(trim(p_model),'\s+',' ','g'),nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),nullif(trim(p_imei_1),''),nullif(trim(p_imei_2),''),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_id,jsonb_build_object('customer_id',p_customer_id)); return v_id; end; $function$
;

CREATE OR REPLACE FUNCTION public.create_reception_customer(p_first_name text, p_last_name text, p_phone text, p_contact_email text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, first_name text, last_name text, phone text, contact_email text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
exception when unique_violation then if v_email is not null and exists(select 1 from public.customers c where c.organization_id=v_org and lower(c.contact_email)=v_email) then raise exception 'CUSTOMER_EMAIL_EXISTS'; else raise exception 'CUSTOMER_PHONE_EXISTS'; end if; end; $function$
;

CREATE OR REPLACE FUNCTION public.current_organization_is_active()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select status = 'ACTIVE' from public.organizations where id = public.current_organization_id()), false)
$function$
;

CREATE OR REPLACE FUNCTION public.current_organization_setup_completed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(initial_setup_completed, false)
  from public.organizations
  where id = public.current_organization_id()
$function$
;

CREATE OR REPLACE FUNCTION public.finalize_initial_organization_setup()
 RETURNS TABLE(status text, incomplete_section text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid := public.current_organization_id();
  v_organization public.organizations%rowtype;
  v_address public.organization_addresses%rowtype;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or not exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'OWNER' and p.status = 'ACTIVE'
        and p.organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;

  select * into v_organization
  from public.organizations
  where id = v_organization_id
  for update;

  if not found then return query select 'UNAVAILABLE'::text, null::text; return; end if;
  if v_organization.status <> 'ACTIVE' then return query select 'SUSPENDED'::text, null::text; return; end if;
  if v_organization.initial_setup_completed then return query select 'ALREADY_COMPLETED'::text, null::text; return; end if;

  if char_length(trim(v_organization.name)) < 2
    or char_length(trim(coalesce(v_organization.trade_name, ''))) < 2 then
    return query select 'INCOMPLETE'::text, 'ORGANIZATION'::text; return;
  end if;
  if coalesce(trim(v_organization.phone), '') !~ '^\+[1-9][0-9]{7,14}$'
    or coalesce(trim(v_organization.contact_email), '') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return query select 'INCOMPLETE'::text, 'CONTACT'::text; return;
  end if;

  select * into v_address
  from public.organization_addresses
  where organization_id = v_organization_id;

  if not found
    or not exists (select 1 from public.countries where id = v_address.country_id and is_active)
    or not exists (select 1 from public.provinces where id = v_address.province_id and country_id = v_address.country_id and is_active)
    or not exists (select 1 from public.localities where id = v_address.locality_id and province_id = v_address.province_id and is_active)
    or (exists (select 1 from public.neighborhoods where locality_id = v_address.locality_id and is_active) and v_address.neighborhood_id is null)
    or (v_address.neighborhood_id is not null and not exists (
      select 1 from public.neighborhoods where id = v_address.neighborhood_id and locality_id = v_address.locality_id and is_active
    ))
    or char_length(trim(v_address.street)) < 2
    or (v_address.without_number and v_address.street_number is not null)
    or (not v_address.without_number and v_address.street_number is null) then
    return query select 'INCOMPLETE'::text, 'LOCATION'::text; return;
  end if;

  update public.organizations
  set initial_setup_completed = true,
      initial_setup_step = 4
  where id = v_organization_id;

  insert into public.audit_events (
    organization_id, actor_user_id, event_type, entity_type, entity_id, result, metadata
  ) values (
    v_organization_id, auth.uid(), 'INITIAL_SETUP_COMPLETED', 'ORGANIZATION', v_organization_id, 'SUCCESS', jsonb_build_object('final_step', 4)
  );

  return query select 'COMPLETED'::text, null::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_first_name text := left(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 80);
  v_last_name text := left(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), 80);
begin
  insert into public.profiles (id, first_name, last_name, display_name, role)
  values (new.id, v_first_name, v_last_name, nullif(concat_ws(' ', v_first_name, v_last_name), ''), 'CUSTOMER')
  on conflict (id) do nothing;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (new.id, 'AUTH_ACCOUNT_CREATED', 'PROFILE', new.id, jsonb_build_object('provider', coalesce(new.raw_app_meta_data ->> 'provider', 'email')));
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.log_audit_event(p_event_type text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (public.current_organization_id(), auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.prevent_profile_privilege_escalation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
    and auth.uid() = old.id
    and (
      new.role is distinct from old.role
      or new.organization_id is distinct from old.organization_id
      or new.status is distinct from old.status
      or new.must_change_password is distinct from old.must_change_password
    )
  then
    raise exception 'Privileged profile fields require an authorized server function';
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.quick_link_url_allowed(p_service text, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_host text;
begin
  if p_url !~ '^https://[^[:space:]]+$' or char_length(p_url) > 2048 then return false; end if;
  v_host := lower(split_part(split_part(substring(p_url from 9), '/', 1), ':', 1));
  if v_host = '' or v_host like '%@%' then return false; end if;
  return case upper(p_service)
    when 'GOOGLE' then v_host = 'google.com' or v_host like '%.google.com'
    when 'GMAIL' then v_host = 'mail.google.com' or v_host like '%.mail.google.com'
    when 'YOUTUBE' then v_host in ('youtube.com', 'youtu.be') or v_host like '%.youtube.com'
    when 'WHATSAPP' then v_host in ('wa.me', 'whatsapp.com') or v_host like '%.whatsapp.com'
    when 'FACEBOOK' then v_host = 'facebook.com' or v_host like '%.facebook.com'
    when 'INSTAGRAM' then v_host = 'instagram.com' or v_host like '%.instagram.com'
    when 'TELEGRAM' then v_host in ('t.me', 'telegram.me') or v_host like '%.telegram.me'
    else false
  end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.register_reception_photo(p_reception_id uuid, p_storage_path text, p_description text, p_inspection_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin perform 1 from public.device_receptions where id=p_reception_id and organization_id=v_org; if not found or p_storage_path not like v_org::text||'/'||p_reception_id::text||'/%' then raise exception 'INVALID_PHOTO'; end if;
 insert into public.reception_photos(organization_id,reception_id,storage_path,description,inspection_item_key,uploaded_by) values(v_org,p_reception_id,p_storage_path,nullif(trim(p_description),''),nullif(p_inspection_key,''),auth.uid()) returning id into v_id; return v_id; end; $function$
;

CREATE OR REPLACE FUNCTION public.replace_own_quick_links(p_links jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer;
begin
  if auth.uid() is null or public.current_app_role() <> 'OWNER' then raise exception 'Forbidden'; end if;
  if not public.current_organization_is_active() or not public.current_organization_setup_completed() then raise exception 'Organization unavailable'; end if;
  if jsonb_typeof(p_links) <> 'array' or jsonb_array_length(p_links) > 7 then raise exception 'Invalid quick links'; end if;
  select count(distinct upper(item ->> 'service')) into v_count from jsonb_array_elements(p_links) item;
  if v_count <> jsonb_array_length(p_links) then raise exception 'Duplicate quick link service'; end if;

  delete from public.user_quick_links where user_id = auth.uid();
  insert into public.user_quick_links (user_id, service, url, enabled)
  select auth.uid(), upper(item ->> 'service'), item ->> 'url', coalesce((item ->> 'enabled')::boolean, true)
  from jsonb_array_elements(p_links) item;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.save_initial_organization_step_one(p_legal_name text, p_commercial_name text, p_logo_path text)
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid := public.current_organization_id();
  v_legal_name text := regexp_replace(trim(p_legal_name), '[[:space:]]+', ' ', 'g');
  v_commercial_name text := regexp_replace(trim(p_commercial_name), '[[:space:]]+', ' ', 'g');
  v_logo_path text := nullif(trim(p_logo_path), '');
  v_next_step smallint;
begin
  if auth.uid() is null or public.current_app_role() <> 'OWNER' then
    raise exception 'Forbidden';
  end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;
  if char_length(v_legal_name) not between 2 and 120
    or v_legal_name ~ '[<>]'
    or v_legal_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid legal name';
  end if;
  if char_length(v_commercial_name) not between 2 and 120
    or v_commercial_name ~ '[<>]'
    or v_commercial_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid commercial name';
  end if;
  if v_logo_path is not null and (
    char_length(v_logo_path) > 500
    or v_logo_path not like v_organization_id::text || '/logo/%'
  ) then
    raise exception 'Invalid logo path';
  end if;

  update public.organizations
  set
    name = v_legal_name,
    trade_name = v_commercial_name,
    logo_path = coalesce(v_logo_path, logo_path),
    initial_setup_step = greatest(initial_setup_step, 2)
  where id = v_organization_id
    and status = 'ACTIVE'
    and initial_setup_completed = false
  returning initial_setup_step into v_next_step;

  if not found then raise exception 'Organization unavailable'; end if;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_organization_id,
    auth.uid(),
    'ORGANIZATION_SETUP_STEP_ONE_SAVED',
    'ORGANIZATION',
    v_organization_id,
    jsonb_build_object('step', 1, 'logo_updated', v_logo_path is not null)
  );

  return v_next_step;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.save_initial_organization_step_three(p_country_id text, p_province_id text, p_locality_id text, p_neighborhood_id text, p_street text, p_street_number integer, p_without_number boolean, p_floor text, p_apartment text, p_postal_code text, p_reference text)
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid := public.current_organization_id();
  v_neighborhood_id text := nullif(trim(p_neighborhood_id), '');
  v_street text := regexp_replace(trim(p_street), '[[:space:]]+', ' ', 'g');
  v_floor text := nullif(regexp_replace(trim(p_floor), '[[:space:]]+', ' ', 'g'), '');
  v_apartment text := nullif(regexp_replace(trim(p_apartment), '[[:space:]]+', ' ', 'g'), '');
  v_postal_code text := nullif(upper(trim(p_postal_code)), '');
  v_reference text := nullif(regexp_replace(trim(p_reference), '[[:space:]]+', ' ', 'g'), '');
  v_next_step smallint;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or not exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'OWNER' and status = 'ACTIVE'
        and organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;
  if not exists (select 1 from public.countries where id = p_country_id and is_active) then raise exception 'Invalid country'; end if;
  if not exists (select 1 from public.provinces where id = p_province_id and country_id = p_country_id and is_active) then raise exception 'Invalid province hierarchy'; end if;
  if not exists (select 1 from public.localities where id = p_locality_id and province_id = p_province_id and is_active) then raise exception 'Invalid locality hierarchy'; end if;
  if exists (select 1 from public.neighborhoods where locality_id = p_locality_id and is_active)
    and v_neighborhood_id is null then raise exception 'Neighborhood required'; end if;
  if v_neighborhood_id is not null and not exists (
    select 1 from public.neighborhoods where id = v_neighborhood_id and locality_id = p_locality_id and is_active
  ) then raise exception 'Invalid neighborhood hierarchy'; end if;
  if char_length(v_street) not between 2 and 120 or v_street ~ '[<>]' or v_street ~ '[[:cntrl:]]' then raise exception 'Invalid street'; end if;
  if (p_without_number and p_street_number is not null)
    or (not p_without_number and (p_street_number is null or p_street_number not between 1 and 999999)) then
    raise exception 'Invalid street number';
  end if;
  if v_floor is not null and char_length(v_floor) > 10 then raise exception 'Invalid floor'; end if;
  if v_apartment is not null and char_length(v_apartment) > 10 then raise exception 'Invalid apartment'; end if;
  if v_postal_code is not null and v_postal_code !~ '^[A-Z0-9-]{4,10}$' then raise exception 'Invalid postal code'; end if;
  if v_reference is not null and (char_length(v_reference) > 200 or v_reference ~ '[<>]' or v_reference ~ '[[:cntrl:]]') then raise exception 'Invalid reference'; end if;

  if not exists (
    select 1 from public.organizations
    where id = v_organization_id and status = 'ACTIVE'
      and initial_setup_completed = false and initial_setup_step >= 3
  ) then raise exception 'Organization unavailable'; end if;

  insert into public.organization_addresses (
    organization_id, country_id, province_id, locality_id, neighborhood_id,
    street, street_number, without_number, floor, apartment, postal_code, reference
  ) values (
    v_organization_id, p_country_id, p_province_id, p_locality_id, v_neighborhood_id,
    v_street, p_street_number, p_without_number, v_floor, v_apartment, v_postal_code, v_reference
  )
  on conflict (organization_id) do update set
    country_id = excluded.country_id,
    province_id = excluded.province_id,
    locality_id = excluded.locality_id,
    neighborhood_id = excluded.neighborhood_id,
    street = excluded.street,
    street_number = excluded.street_number,
    without_number = excluded.without_number,
    floor = excluded.floor,
    apartment = excluded.apartment,
    postal_code = excluded.postal_code,
    reference = excluded.reference;

  update public.organizations
  set initial_setup_step = greatest(initial_setup_step, 4)
  where id = v_organization_id
  returning initial_setup_step into v_next_step;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization_id, auth.uid(), 'ORGANIZATION_SETUP_STEP_THREE_SAVED', 'ORGANIZATION', v_organization_id, jsonb_build_object('step', 3));

  return v_next_step;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.save_initial_organization_step_two(p_phone text, p_contact_email text)
 RETURNS smallint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_organization_id uuid := public.current_organization_id();
  v_phone text := trim(p_phone);
  v_contact_email text := lower(trim(p_contact_email));
  v_next_step smallint;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or not exists (
      select 1
      from public.profiles
      where id = auth.uid()
        and role = 'OWNER'
        and status = 'ACTIVE'
        and organization_id = v_organization_id
    ) then
    raise exception 'Forbidden';
  end if;
  if v_organization_id is null then raise exception 'Organization required'; end if;

  -- El servidor de aplicación valida el número con libphonenumber; PostgreSQL
  -- conserva además la forma canónica E.164 como defensa estructural.
  if v_phone is null or v_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'Invalid phone';
  end if;
  if v_contact_email is null
    or char_length(v_contact_email) > 254
    or v_contact_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid email';
  end if;

  update public.organizations
  set
    phone = v_phone,
    contact_email = v_contact_email,
    initial_setup_step = greatest(initial_setup_step, 3)
  where id = v_organization_id
    and status = 'ACTIVE'
    and initial_setup_completed = false
    and initial_setup_step >= 2
  returning initial_setup_step into v_next_step;

  if not found then raise exception 'Organization unavailable'; end if;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_organization_id,
    auth.uid(),
    'ORGANIZATION_SETUP_STEP_TWO_SAVED',
    'ORGANIZATION',
    v_organization_id,
    jsonb_build_object('step', 2)
  );

  return v_next_step;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.update_own_superadmin_profile(p_first_name text, p_last_name text, p_display_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_first_name text := regexp_replace(trim(p_first_name), '[[:space:]]+', ' ', 'g');
  v_last_name text := regexp_replace(trim(p_last_name), '[[:space:]]+', ' ', 'g');
  v_display_name text := regexp_replace(trim(p_display_name), '[[:space:]]+', ' ', 'g');
begin
  if auth.uid() is null or public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if char_length(v_first_name) not between 2 and 80 or char_length(v_last_name) not between 2 and 80 or char_length(v_display_name) not between 2 and 170 then raise exception 'Invalid profile'; end if;
  update public.profiles set first_name = v_first_name, last_name = v_last_name, display_name = v_display_name where id = auth.uid();
  if not found then raise exception 'Profile not found'; end if;
end;
$function$
;

grant delete on table "public"."gpu_brands" to "anon";

grant insert on table "public"."gpu_brands" to "anon";

grant references on table "public"."gpu_brands" to "anon";

grant select on table "public"."gpu_brands" to "anon";

grant trigger on table "public"."gpu_brands" to "anon";

grant truncate on table "public"."gpu_brands" to "anon";

grant update on table "public"."gpu_brands" to "anon";

grant delete on table "public"."gpu_brands" to "authenticated";

grant insert on table "public"."gpu_brands" to "authenticated";

grant references on table "public"."gpu_brands" to "authenticated";

grant select on table "public"."gpu_brands" to "authenticated";

grant trigger on table "public"."gpu_brands" to "authenticated";

grant truncate on table "public"."gpu_brands" to "authenticated";

grant update on table "public"."gpu_brands" to "authenticated";

grant delete on table "public"."gpu_brands" to "service_role";

grant insert on table "public"."gpu_brands" to "service_role";

grant references on table "public"."gpu_brands" to "service_role";

grant select on table "public"."gpu_brands" to "service_role";

grant trigger on table "public"."gpu_brands" to "service_role";

grant truncate on table "public"."gpu_brands" to "service_role";

grant update on table "public"."gpu_brands" to "service_role";

grant delete on table "public"."gpu_families" to "anon";

grant insert on table "public"."gpu_families" to "anon";

grant references on table "public"."gpu_families" to "anon";

grant select on table "public"."gpu_families" to "anon";

grant trigger on table "public"."gpu_families" to "anon";

grant truncate on table "public"."gpu_families" to "anon";

grant update on table "public"."gpu_families" to "anon";

grant delete on table "public"."gpu_families" to "authenticated";

grant insert on table "public"."gpu_families" to "authenticated";

grant references on table "public"."gpu_families" to "authenticated";

grant select on table "public"."gpu_families" to "authenticated";

grant trigger on table "public"."gpu_families" to "authenticated";

grant truncate on table "public"."gpu_families" to "authenticated";

grant update on table "public"."gpu_families" to "authenticated";

grant delete on table "public"."gpu_families" to "service_role";

grant insert on table "public"."gpu_families" to "service_role";

grant references on table "public"."gpu_families" to "service_role";

grant select on table "public"."gpu_families" to "service_role";

grant trigger on table "public"."gpu_families" to "service_role";

grant truncate on table "public"."gpu_families" to "service_role";

grant update on table "public"."gpu_families" to "service_role";

grant delete on table "public"."gpu_models" to "anon";

grant insert on table "public"."gpu_models" to "anon";

grant references on table "public"."gpu_models" to "anon";

grant select on table "public"."gpu_models" to "anon";

grant trigger on table "public"."gpu_models" to "anon";

grant truncate on table "public"."gpu_models" to "anon";

grant update on table "public"."gpu_models" to "anon";

grant delete on table "public"."gpu_models" to "authenticated";

grant insert on table "public"."gpu_models" to "authenticated";

grant references on table "public"."gpu_models" to "authenticated";

grant select on table "public"."gpu_models" to "authenticated";

grant trigger on table "public"."gpu_models" to "authenticated";

grant truncate on table "public"."gpu_models" to "authenticated";

grant update on table "public"."gpu_models" to "authenticated";

grant delete on table "public"."gpu_models" to "service_role";

grant insert on table "public"."gpu_models" to "service_role";

grant references on table "public"."gpu_models" to "service_role";

grant select on table "public"."gpu_models" to "service_role";

grant trigger on table "public"."gpu_models" to "service_role";

grant truncate on table "public"."gpu_models" to "service_role";

grant update on table "public"."gpu_models" to "service_role";


