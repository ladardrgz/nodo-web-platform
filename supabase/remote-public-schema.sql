


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."app_role" AS ENUM (
    'SUPERADMIN',
    'OWNER',
    'CUSTOMER',
    'TECHNICIAN'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE TYPE "public"."inventory_movement_type" AS ENUM (
    'IN',
    'OUT',
    'ADJUSTMENT'
);


ALTER TYPE "public"."inventory_movement_type" OWNER TO "postgres";


CREATE TYPE "public"."organization_status" AS ENUM (
    'ACTIVE',
    'SUSPENDED'
);


ALTER TYPE "public"."organization_status" OWNER TO "postgres";


CREATE TYPE "public"."profile_status" AS ENUM (
    'ACTIVE',
    'SUSPENDED',
    'DISABLED'
);


ALTER TYPE "public"."profile_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid" DEFAULT NULL::"uuid", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_inventory_owner"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_organization_id uuid := public.current_organization_id();
begin
  if v_organization_id is null
    or not public.has_inventory_owner_access(v_organization_id)
  then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return v_organization_id;
end;
$$;


ALTER FUNCTION "public"."assert_inventory_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_reception_owner"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid;
begin
 select p.organization_id into v_org from public.profiles p join public.organizations o on o.id=p.organization_id where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and o.status='ACTIVE' and o.initial_setup_completed;
 if v_org is null then raise exception 'FORBIDDEN'; end if; return v_org;
end; $$;


ALTER FUNCTION "public"."assert_reception_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_profile_data_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if old.first_name is distinct from new.first_name or old.last_name is distinct from new.last_name or old.display_name is distinct from new.display_name then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (new.organization_id, auth.uid(), 'PROFILE_UPDATED', 'PROFILE', new.id, jsonb_build_object('personal_data', true));
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."audit_profile_data_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_my_pending_deletion"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_request public.account_deletion_requests%rowtype;
begin
  select * into v_request
  from public.account_deletion_requests
  where status = 'PENDING' and (
    target_user_id = auth.uid()
    or requested_by = auth.uid()
    or (subject_type='ORGANIZATION' and exists (
      select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=account_deletion_requests.organization_id
    ))
  )
  order by requested_at desc limit 1 for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if v_request.scheduled_for <= now() then raise exception 'RECOVERY_PERIOD_EXPIRED'; end if;

  if v_request.subject_type = 'ORGANIZATION' then
    update public.organizations set status = 'ACTIVE' where id = v_request.organization_id and status = 'SUSPENDED';
  else
    update public.profiles set status = 'ACTIVE' where id = auth.uid() and status = 'SUSPENDED';
  end if;
  update public.account_deletion_requests set status = 'CANCELLED', cancelled_at = now() where id = v_request.id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_request.organization_id, auth.uid(), v_request.subject_type || '_DELETION_CANCELLED', v_request.subject_type,
    coalesce(v_request.organization_id, auth.uid()), jsonb_build_object('request_id', v_request.id, 'status', 'CANCELLED'));
  return jsonb_build_object('ok', true, 'subjectType', v_request.subject_type);
end;
$$;


ALTER FUNCTION "public"."cancel_my_pending_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_password_change"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set must_change_password = false where id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."complete_password_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'RECEPTION_CONFIRMED','DEVICE_RECEPTION',v_id,jsonb_build_object('device_id',p_device_id,'condition',v_condition)); return v_id; end; $$;


ALTER FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") RETURNS TABLE("allowed" boolean, "retry_after_seconds" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."device_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "categories" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_brands_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 80)))
);


ALTER TABLE "public"."device_brands" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_custom_device_brand"("p_name" "text") RETURNS SETOF "public"."device_brands"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_BRAND'; end if;
 if exists(select 1 from public.device_brands where (organization_id is null or organization_id=v_org) and lower(name)=lower(v_name)) then raise exception 'DEVICE_BRAND_EXISTS'; end if;
 insert into public.device_brands(organization_id,name,created_by) values(v_org,v_name,auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_BRAND_CREATED','DEVICE_BRAND',v_id,'{}'); return query select * from public.device_brands where id=v_id; end; $$;


ALTER FUNCTION "public"."create_custom_device_brand"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") RETURNS SETOF "public"."device_brands"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_colors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_colors_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 80)))
);


ALTER TABLE "public"."device_colors" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_custom_device_color"("p_name" "text") RETURNS SETOF "public"."device_colors"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin
 if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_COLOR'; end if;
 if exists(select 1 from public.device_colors where (organization_id is null or organization_id=v_org) and lower(regexp_replace(trim(name),'\s+',' ','g'))=lower(v_name)) then raise exception 'DEVICE_COLOR_EXISTS'; end if;
 insert into public.device_colors(organization_id,name,created_by) values(v_org,v_name,auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_COLOR_CREATED','DEVICE_COLOR',v_id,'{}');
 return query select * from public.device_colors where id=v_id;
end; $$;


ALTER FUNCTION "public"."create_custom_device_color"("p_name" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "device_type_id" "uuid" NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "family_id" "uuid",
    "technical_code" "text",
    CONSTRAINT "device_models_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 120)))
);


ALTER TABLE "public"."device_models" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_models" IS 'Catálogo de modelos base o privados por organización; la fuente se deriva de organization_id nulo o no nulo.';



CREATE OR REPLACE FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") RETURNS SETOF "public"."device_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "attribute_group" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_types_attribute_group_check" CHECK (("attribute_group" = ANY (ARRAY['MOBILE'::"text", 'COMPUTER'::"text", 'PRINTER'::"text", 'DISPLAY'::"text", 'NETWORK'::"text", 'GAMING'::"text", 'CAMERA'::"text", 'STORAGE'::"text", 'AUDIO'::"text", 'PERIPHERAL'::"text", 'POWER'::"text", 'COMMERCIAL'::"text", 'OTHER'::"text"]))),
    CONSTRAINT "device_types_category_check" CHECK ((("char_length"("category") >= 2) AND ("char_length"("category") <= 80))),
    CONSTRAINT "device_types_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 80)))
);


ALTER TABLE "public"."device_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_types" IS 'Tipos globales y por organización. Los duplicados se desactivan para nuevas altas; nunca se borran si pueden estar referenciados históricamente.';



CREATE OR REPLACE FUNCTION "public"."create_custom_device_type"("p_name" "text") RETURNS SETOF "public"."device_types"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_TYPE'; end if;
 if exists(select 1 from public.device_types where (organization_id is null or organization_id=v_org) and lower(name)=lower(v_name)) then raise exception 'DEVICE_TYPE_EXISTS'; end if;
 insert into public.device_types(organization_id,name,category,attribute_group,created_by) values(v_org,v_name,'Personalizados','OTHER',auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_TYPE_CREATED','DEVICE_TYPE',v_id,'{}'); return query select * from public.device_types where id=v_id; end; $$;


ALTER FUNCTION "public"."create_custom_device_type"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin
 perform 1 from public.customers where id=p_customer_id and organization_id=v_org; if not found then raise exception 'INVALID_CUSTOMER'; end if;
 perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
 perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
 insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
 values(v_org,p_customer_id,p_type_id,p_brand_id,regexp_replace(trim(p_model),'\s+',' ','g'),nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),nullif(trim(p_imei_1),''),nullif(trim(p_imei_2),''),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_id,jsonb_build_object('customer_id',p_customer_id)); return v_id; end; $$;


ALTER FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_device_id uuid; v_is_pc boolean; v_is_notebook boolean; v_model text:=regexp_replace(btrim(coalesce(p_model,'')),'[[:space:]]+',' ','g'); v_attributes jsonb;
begin
  select name='PC',name='Notebook' into v_is_pc,v_is_notebook from public.device_types where id=p_type_id;
  if not coalesce(v_is_pc,false) and char_length(v_model) < 2 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into v_attributes from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) where nullif(regexp_replace(trim(value #>> '{}'),'[[:space:]]+',' ','g'),'') is not null;
  v_device_id:=public.create_customer_device_dynamic_legacy(p_customer_id,p_type_id,p_brand_id,p_model_id,case when coalesce(v_is_pc,false) and v_model='' then '__unknown__' else v_model end,p_year,p_color,p_serial_number,p_imei_1,p_imei_2,v_attributes,p_memories,p_storage_units,p_accessories);
  update public.customer_devices set model=case when coalesce(v_is_pc,false) and v_model='' then null else model end, memory_modules=case when coalesce(v_is_notebook,false) and coalesce(jsonb_array_length(p_memories),0)=0 then null else memory_modules end, storage_units=case when coalesce(v_is_notebook,false) and coalesce(jsonb_array_length(p_storage_units),0)=0 then null else storage_units end, accessories=case when coalesce(v_is_notebook,false) and coalesce(cardinality(p_accessories),0)=0 then null else accessories end where id=v_device_id;
  return v_device_id;
end; $$;


ALTER FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_org uuid:=public.assert_reception_owner(); v_device_id uuid; v_model text:=regexp_replace(trim(p_model),'\s+',' ','g');
  v_item record; v_field record; v_text text; v_option uuid;
begin
  perform 1 from public.customers where id=p_customer_id and organization_id=v_org;
  if not found then raise exception 'INVALID_CUSTOMER'; end if;
  perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org);
  if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
  perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org);
  if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if char_length(v_model) not between 2 and 120 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_model_id is not null then
    perform 1 from public.device_models where id=p_model_id and device_type_id=p_type_id and brand_id=p_brand_id and is_active and (organization_id is null or organization_id=v_org);
    if not found then raise exception 'INVALID_DEVICE_MODEL'; end if;
  end if;
  if jsonb_typeof(coalesce(p_attributes,'{}'::jsonb)) <> 'object' then raise exception 'INVALID_DEVICE_FIELDS'; end if;
  for v_field in
    select tf.id, f.key, tf.required from public.device_type_fields tf
    join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and tf.required
  loop
    if nullif(trim(coalesce(p_attributes->>v_field.key,'')),'') is null then
      raise exception 'REQUIRED_DEVICE_FIELD';
    end if;
  end loop;
  for v_item in select key,value from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) loop
    select tf.id, f.id as field_id, f.field_type, f.data_source_key, tf.required
    into v_field from public.device_type_fields tf join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and f.key=v_item.key
    limit 1;
    if v_field.id is null then raise exception 'INVALID_DEVICE_FIELD'; end if;
    v_text:=nullif(regexp_replace(trim(coalesce(v_item.value #>> '{}','')),'\s+',' ','g'),'');
    if v_field.required and v_text is null then raise exception 'REQUIRED_DEVICE_FIELD'; end if;
  end loop;
  insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
  values(v_org,p_customer_id,p_type_id,p_brand_id,p_model_id,v_model,nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),coalesce(nullif(trim(p_imei_1),''),nullif(p_attributes->>'imei_1','')),coalesce(nullif(trim(p_imei_2),''),nullif(p_attributes->>'imei_2','')),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_device_id;
  for v_item in select key,value from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) loop
    select tf.id, f.id as field_id, f.field_type, f.data_source_key into v_field
    from public.device_type_fields tf join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and f.key=v_item.key limit 1;
    v_text:=nullif(regexp_replace(trim(coalesce(v_item.value #>> '{}','')),'\s+',' ','g'),'');
    if v_text is null then continue; end if;
    v_option:=null;
    if v_field.data_source_key is null and v_field.field_type in ('SELECT','RADIO') then
      select id into v_option from public.device_field_options where field_id=v_field.field_id and is_active and value=v_text and (organization_id is null or organization_id=v_org) order by organization_id nulls first limit 1;
      if v_option is null then raise exception 'INVALID_DEVICE_FIELD_OPTION'; end if;
    end if;
    insert into public.customer_device_field_values(organization_id,customer_device_id,device_type_field_id,option_id,value_text,value_boolean)
    values(v_org,v_device_id,v_field.id,v_option,case when v_option is null and v_field.field_type not in ('SWITCH','CHECKBOX') then v_text else null end,case when v_field.field_type in ('SWITCH','CHECKBOX') then (v_text='true') else null end)
    on conflict(customer_device_id,device_type_field_id) do update set option_id=excluded.option_id,value_text=excluded.value_text,value_boolean=excluded.value_boolean,updated_at=now();
  end loop;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_device_id,jsonb_build_object('customer_id',p_customer_id,'model_id',p_model_id,'dynamic_form',true));
  return v_device_id;
end; $$;


ALTER FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_catalog_name"("p_value" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
  select translate(
    lower(regexp_replace(btrim(p_value), '[[:space:]]+', ' ', 'g')),
    'áéíóúüñ',
    'aeiouun'
  )
$$;


ALTER FUNCTION "public"."normalize_catalog_name"("p_value" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") IS 'Normaliza espacios, mayúsculas y diacríticos para comparar catálogos sin alterar el nombre visible.';



CREATE TABLE IF NOT EXISTS "public"."hardware_catalog_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "kind" "text" NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hardware_catalog_models_kind_check" CHECK (("kind" = ANY (ARRAY['PROCESSOR'::"text", 'MOTHERBOARD'::"text", 'GPU'::"text", 'POWER_SUPPLY'::"text", 'CASE'::"text", 'CPU_COOLER'::"text", 'WIFI_ADAPTER'::"text"]))),
    CONSTRAINT "hardware_catalog_models_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 200)))
);


ALTER TABLE "public"."hardware_catalog_models" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") RETURNS "public"."hardware_catalog_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_org uuid := public.assert_reception_owner();
  v_kind text := upper(btrim(coalesce(p_kind, '')));
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '[[:space:]]+', ' ', 'g');
  v_brand public.hardware_catalog_brands;
  v_existing public.hardware_catalog_models;
  v_created public.hardware_catalog_models;
begin
  if v_kind not in ('PROCESSOR','MOTHERBOARD','GPU','POWER_SUPPLY','CASE','CPU_COOLER','WIFI_ADAPTER') then raise exception 'INVALID_HARDWARE_KIND'; end if;
  if char_length(v_name) not between 2 and 200 then raise exception 'INVALID_HARDWARE_MODEL'; end if;
  select * into v_brand from public.hardware_catalog_brands
    where id = p_brand_id and kind = v_kind and is_active and (organization_id is null or organization_id = v_org);
  if not found then raise exception 'INVALID_HARDWARE_BRAND'; end if;
  select * into v_existing from public.hardware_catalog_models
    where kind = v_kind and brand_id = p_brand_id and normalized_name = public.normalize_catalog_name(v_name)
      and is_active and (organization_id is null or organization_id = v_org)
    order by organization_id nulls first limit 1;
  if found then return v_existing; end if;
  insert into public.hardware_catalog_models(organization_id, kind, brand_id, name, created_by)
  values (v_org, v_kind, p_brand_id, v_name, auth.uid())
  on conflict (organization_id, kind, brand_id, normalized_name) where organization_id is not null do update set name = hardware_catalog_models.name
  returning * into v_created;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values(v_org, auth.uid(), 'HARDWARE_CATALOG_MODEL_CREATED', 'HARDWARE_CATALOG_MODEL', v_created.id, jsonb_build_object('kind', v_kind, 'brand_id', p_brand_id));
  return v_created;
end; $$;


ALTER FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "first_name" "text", "last_name" "text", "phone" "text", "contact_email" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
exception when unique_violation then if v_email is not null and exists(select 1 from public.customers c where c.organization_id=v_org and lower(c.contact_email)=v_email) then raise exception 'CUSTOMER_EMAIL_EXISTS'; else raise exception 'CUSTOMER_PHONE_EXISTS'; end if; end; $_$;


ALTER FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_app_role"() RETURNS "public"."app_role"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select p.role
  from public.profiles p
  left join public.organizations o on o.id = p.organization_id
  where p.id = auth.uid()
    and p.status = 'ACTIVE'
    and (p.role = 'SUPERADMIN' or (o.id is not null and o.status = 'ACTIVE'))
$$;


ALTER FUNCTION "public"."current_app_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select organization_id from public.profiles where id = auth.uid() $$;


ALTER FUNCTION "public"."current_organization_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_is_active"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce((select status = 'ACTIVE' from public.organizations where id = public.current_organization_id()), false)
$$;


ALTER FUNCTION "public"."current_organization_is_active"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_setup_completed"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(initial_setup_completed, false)
  from public.organizations
  where id = public.current_organization_id()
$$;


ALTER FUNCTION "public"."current_organization_setup_completed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_due_account_deletions"() RETURNS TABLE("request_id" "uuid", "subject_type" "text", "organization_id" "uuid", "target_user_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_request public.account_deletion_requests%rowtype;
  v_open integer;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then raise exception 'FORBIDDEN'; end if;
  for v_request in
    select * from public.account_deletion_requests where status = 'PENDING' and scheduled_for <= now() order by scheduled_for for update skip locked
  loop
    if v_request.subject_type = 'ORGANIZATION' then
      select count(*) into v_open from public.device_receptions where organization_id = v_request.organization_id and status = 'CONFIRMED';
    else
      select count(*) into v_open from public.device_receptions r join public.customer_user_links l on l.customer_id=r.customer_id and l.organization_id=r.organization_id
      where l.auth_user_id=v_request.target_user_id and r.status='CONFIRMED';
    end if;
    if v_open > 0 then continue; end if;

    if v_request.subject_type = 'CUSTOMER_ACCOUNT' then
      update public.customers c set portal_account_deleted_at = now()
      where exists (select 1 from public.customer_user_links l where l.customer_id=c.id and l.organization_id=c.organization_id and l.auth_user_id=v_request.target_user_id);
      delete from public.customer_user_links where auth_user_id=v_request.target_user_id;
      delete from public.user_quick_links where user_id=v_request.target_user_id;
      update public.profiles set first_name=null,last_name=null,display_name='Cuenta eliminada',status='DISABLED' where id=v_request.target_user_id;
    else
      delete from public.user_quick_links where user_id in (select id from public.profiles where organization_id=v_request.organization_id);
      update public.profiles set first_name=null,last_name=null,display_name='Cuenta eliminada',status='DISABLED' where organization_id=v_request.organization_id;
    end if;

    update public.account_deletion_requests set status='COMPLETED',completed_at=now() where id=v_request.id;
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_request.organization_id, null, v_request.subject_type || '_DELETION_COMPLETED', v_request.subject_type,
      coalesce(v_request.organization_id, v_request.target_user_id), jsonb_build_object('request_id',v_request.id,'status','COMPLETED'));
    request_id:=v_request.id; subject_type:=v_request.subject_type; organization_id:=v_request.organization_id; target_user_id:=v_request.target_user_id;
    return next;
  end loop;
end;
$$;


ALTER FUNCTION "public"."finalize_due_account_deletions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_initial_organization_setup"() RETURNS TABLE("status" "text", "incomplete_section" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."finalize_initial_organization_setup"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."finalize_initial_organization_setup"() IS 'Valida datos persistidos, completa el onboarding y registra auditoría en una única transacción idempotente.';



CREATE OR REPLACE FUNCTION "public"."get_my_pending_deletion"() RETURNS TABLE("id" "uuid", "subject_type" "text", "organization_id" "uuid", "reason" "text", "requested_at" timestamp with time zone, "scheduled_for" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select r.id, r.subject_type, r.organization_id, r.reason, r.requested_at, r.scheduled_for
  from public.account_deletion_requests r
  where r.status = 'PENDING'
    and (
      r.target_user_id = auth.uid()
      or r.requested_by = auth.uid()
      or (r.subject_type='ORGANIZATION' and exists (
        select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=r.organization_id
      ))
    )
  order by r.requested_at desc
  limit 1
$$;


ALTER FUNCTION "public"."get_my_pending_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.profiles p
    join public.organizations o on o.id = p.organization_id
    where p.id = auth.uid()
      and p.organization_id = p_organization_id
      and p.role = 'OWNER'
      and p.status = 'ACTIVE'
      and o.status = 'ACTIVE'
      and o.initial_setup_completed
  )
$$;


ALTER FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text" DEFAULT NULL::"text", "p_entity_id" "uuid" DEFAULT NULL::"uuid", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_id uuid;
begin
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (public.current_organization_id(), auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if current_user not in ('postgres','service_role','supabase_admin') then raise exception 'FORBIDDEN'; end if;
  update public.account_deletion_requests set auth_cleanup_completed=true where id=p_request_id and status='COMPLETED';
end; $$;


ALTER FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_confirmed_reception_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin raise exception 'CONFIRMED_RECEPTION_IMMUTABLE'; end; $$;


ALTER FUNCTION "public"."prevent_confirmed_reception_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_inventory_movement_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  raise exception 'Inventory movements are immutable';
end;
$$;


ALTER FUNCTION "public"."prevent_inventory_movement_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_inventory_stock_direct_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.current_stock is distinct from old.current_stock
    and coalesce(current_setting('nodo.inventory_stock_write', true), 'off') <> 'on'
  then
    raise exception 'Inventory stock must be changed through record_inventory_movement';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."prevent_inventory_stock_direct_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_profile_privilege_escalation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."prevent_profile_privilege_escalation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_inventory_record_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.organization_id is distinct from old.organization_id
    or new.created_by is distinct from old.created_by
  then
    raise exception 'Inventory ownership fields are immutable';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."protect_inventory_record_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric DEFAULT NULL::numeric, "p_reference_type" "text" DEFAULT NULL::"text", "p_reference_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_organization_id uuid := public.assert_inventory_owner();
  v_movement_id uuid;
  v_stock_before numeric(14,3);
  v_stock_after numeric(14,3);
  v_quantity_delta numeric(14,3);
  v_reason text := regexp_replace(btrim(coalesce(p_reason, '')), '[[:space:]]+', ' ', 'g');
  v_reference_type text := nullif(
    upper(regexp_replace(btrim(coalesce(p_reference_type, '')), '[[:space:]]+', '_', 'g')),
    ''
  );
begin
  if p_movement_type is null or p_quantity is null or p_quantity = 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  if p_movement_type in ('IN', 'OUT') and p_quantity < 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  v_quantity_delta := case p_movement_type
    when 'IN' then p_quantity
    when 'OUT' then -p_quantity
    when 'ADJUSTMENT' then p_quantity
  end;

  if char_length(v_reason) not between 3 and 500 then
    raise exception 'INVALID_REASON';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'INVALID_UNIT_COST';
  end if;

  if (v_reference_type is null) <> (p_reference_id is null) then
    raise exception 'INVALID_REFERENCE';
  end if;

  if v_reference_type is not null
    and v_reference_type !~ '^[A-Z][A-Z0-9_]{1,49}$'
  then
    raise exception 'INVALID_REFERENCE_TYPE';
  end if;

  select i.current_stock
  into v_stock_before
  from public.inventory_items i
  where i.id = p_inventory_item_id
    and i.organization_id = v_organization_id
    and i.is_active
  for update;

  if not found then
    raise exception 'INVENTORY_ITEM_NOT_FOUND';
  end if;

  v_stock_after := v_stock_before + v_quantity_delta;
  if v_stock_after < 0 then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  perform set_config('nodo.inventory_stock_write', 'on', true);
  update public.inventory_items
  set current_stock = v_stock_after
  where id = p_inventory_item_id
    and organization_id = v_organization_id;
  perform set_config('nodo.inventory_stock_write', 'off', true);

  insert into public.inventory_movements (
    organization_id,
    inventory_item_id,
    movement_type,
    quantity_delta,
    stock_before,
    stock_after,
    unit_cost,
    reason,
    reference_type,
    reference_id,
    actor_user_id
  ) values (
    v_organization_id,
    p_inventory_item_id,
    p_movement_type,
    v_quantity_delta,
    v_stock_before,
    v_stock_after,
    p_unit_cost,
    v_reason,
    v_reference_type,
    p_reference_id,
    auth.uid()
  )
  returning id into v_movement_id;

  return v_movement_id;
end;
$_$;


ALTER FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") IS 'Registra IN/OUT con cantidad positiva; ADJUSTMENT admite una diferencia con signo. Rechaza saldos negativos.';



CREATE OR REPLACE FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin perform 1 from public.device_receptions where id=p_reception_id and organization_id=v_org; if not found or p_storage_path not like v_org::text||'/'||p_reception_id::text||'/%' then raise exception 'INVALID_PHOTO'; end if;
 insert into public.reception_photos(organization_id,reception_id,storage_path,description,inspection_item_key,uploaded_by) values(v_org,p_reception_id,p_storage_path,nullif(trim(p_description),''),nullif(p_inspection_key,''),auth.uid()) returning id into v_id; return v_id; end; $$;


ALTER FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile public.profiles%rowtype;
  v_reason text := regexp_replace(trim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_open_receptions integer;
  v_request_id uuid;
  v_scheduled_for timestamptz := now() + interval '30 days';
begin
  select * into v_profile from public.profiles where id = auth.uid() for update;
  if not found or v_profile.role <> 'CUSTOMER' or v_profile.status <> 'ACTIVE' then raise exception 'FORBIDDEN'; end if;
  if v_profile.organization_id is not null and not exists (
    select 1 from public.organizations where id=v_profile.organization_id and status='ACTIVE'
  ) then raise exception 'ORGANIZATION_UNAVAILABLE'; end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'INVALID_REASON'; end if;

  select count(*) into v_open_receptions
  from public.device_receptions r
  join public.customer_user_links l
    on l.customer_id = r.customer_id and l.organization_id = r.organization_id
  where l.auth_user_id = auth.uid() and r.status = 'CONFIRMED';

  if v_open_receptions > 0 then
    return jsonb_build_object(
      'ok', false,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'OPEN_RECEPTIONS',
        'count', v_open_receptions,
        'message', format('Tenés %s reparacion(es) o equipo(s) pendientes de resolución/retiro.', v_open_receptions)
      ))
    );
  end if;

  insert into public.account_deletion_requests
    (subject_type, organization_id, target_user_id, requested_by, reason, scheduled_for)
  values ('CUSTOMER_ACCOUNT', v_profile.organization_id, auth.uid(), auth.uid(), v_reason, v_scheduled_for)
  returning id into v_request_id;

  update public.profiles set status = 'SUSPENDED' where id = auth.uid();
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_profile.organization_id, auth.uid(), 'CUSTOMER_ACCOUNT_DELETION_REQUESTED', 'PROFILE', auth.uid(),
    jsonb_build_object('request_id', v_request_id, 'reason', v_reason, 'status', 'PENDING', 'scheduled_for', v_scheduled_for));

  return jsonb_build_object('ok', true, 'requestId', v_request_id, 'scheduledFor', v_scheduled_for);
end;
$$;


ALTER FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_organization_deletion"("p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile public.profiles%rowtype;
  v_organization public.organizations%rowtype;
  v_reason text := regexp_replace(trim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_open_receptions integer;
  v_request_id uuid;
  v_scheduled_for timestamptz := now() + interval '30 days';
begin
  select * into v_profile from public.profiles where id = auth.uid() for update;
  if not found or v_profile.role <> 'OWNER' or v_profile.status <> 'ACTIVE' or v_profile.organization_id is null then
    raise exception 'FORBIDDEN';
  end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'INVALID_REASON'; end if;

  select * into v_organization from public.organizations where id = v_profile.organization_id for update;
  if not found or v_organization.status <> 'ACTIVE' then raise exception 'ORGANIZATION_UNAVAILABLE'; end if;

  select count(*) into v_open_receptions
  from public.device_receptions
  where organization_id = v_organization.id and status = 'CONFIRMED';

  if v_open_receptions > 0 then
    return jsonb_build_object(
      'ok', false,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'OPEN_RECEPTIONS',
        'count', v_open_receptions,
        'message', format('Hay %s reparacion(es) o equipo(s) pendientes de resolución/retiro.', v_open_receptions)
      ))
    );
  end if;

  insert into public.account_deletion_requests
    (subject_type, organization_id, requested_by, reason, scheduled_for)
  values ('ORGANIZATION', v_organization.id, auth.uid(), v_reason, v_scheduled_for)
  returning id into v_request_id;

  update public.organizations set status = 'SUSPENDED' where id = v_organization.id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization.id, auth.uid(), 'ORGANIZATION_DELETION_REQUESTED', 'ORGANIZATION', v_organization.id,
    jsonb_build_object('request_id', v_request_id, 'reason', v_reason, 'status', 'PENDING', 'scheduled_for', v_scheduled_for));

  return jsonb_build_object('ok', true, 'requestId', v_request_id, 'scheduledFor', v_scheduled_for);
end;
$$;


ALTER FUNCTION "public"."request_organization_deletion"("p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ delete from public.auth_rate_limits where action = upper(p_action) and key_hash = p_key_hash $$;


ALTER FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") IS 'Guarda únicamente identidad y logo del OWNER autenticado y avanza el onboarding al paso 2.';



CREATE OR REPLACE FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") IS 'Guarda únicamente teléfono E.164 y email de contacto del OWNER autenticado y avanza el onboarding al paso 3.';



CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_organization_id uuid := public.current_organization_id();
  v_name text := regexp_replace(trim(p_name), '[[:space:]]+', ' ', 'g');
  v_logo_path text := nullif(trim(p_logo_path), '');
  v_phone text := trim(p_phone);
  v_phone_country_code text := upper(trim(p_phone_country_code));
  v_phone_calling_code text := trim(p_phone_calling_code);
  v_phone_national_number text := trim(p_phone_national_number);
  v_contact_email text := lower(trim(p_contact_email));
  v_neighborhood_id text := nullif(trim(p_neighborhood_id), '');
  v_street text := regexp_replace(trim(p_street), '[[:space:]]+', ' ', 'g');
  v_locality_name text;
  v_province_name text;
  v_old_logo_path text;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or v_organization_id is null
    or not exists (
      select 1 from public.profiles
      where id = auth.uid()
        and role = 'OWNER'
        and status = 'ACTIVE'
        and organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;

  select logo_path into v_old_logo_path
  from public.organizations
  where id = v_organization_id and status = 'ACTIVE' and initial_setup_completed
  for update;
  if not found then raise exception 'Organization not available'; end if;

  if char_length(v_name) not between 2 and 120 or v_name ~ '[<>]' or v_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid organization name';
  end if;
  if v_phone_country_code !~ '^[A-Z]{2}$'
    or v_phone_calling_code !~ '^\+[1-9][0-9]{0,3}$'
    or v_phone_national_number !~ '^[0-9]{4,15}$'
    or v_phone <> v_phone_calling_code || v_phone_national_number
    or (v_phone_country_code = 'AR' and char_length(v_phone_national_number) <> 10) then
    raise exception 'Invalid phone';
  end if;
  if v_contact_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or char_length(v_contact_email) > 254 then
    raise exception 'Invalid email';
  end if;
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
  if v_logo_path is not null and (
    char_length(v_logo_path) > 500
    or v_logo_path not like v_organization_id::text || '/%'
    or v_logo_path like '%..%'
  ) then raise exception 'Invalid logo path'; end if;

  select name into v_locality_name from public.localities where id = p_locality_id;
  select name into v_province_name from public.provinces where id = p_province_id;

  update public.organizations
  set
    name = v_name,
    trade_name = v_name,
    logo_path = v_logo_path,
    phone = v_phone,
    phone_country_code = v_phone_country_code,
    phone_calling_code = v_phone_calling_code,
    phone_national_number = v_phone_national_number,
    contact_email = v_contact_email,
    address = v_street || ' ' || case when p_without_number then 'S/N' else p_street_number::text end,
    locality = v_locality_name,
    province = v_province_name
  where id = v_organization_id;

  insert into public.organization_addresses (
    organization_id, country_id, province_id, locality_id, neighborhood_id,
    street, street_number, without_number
  ) values (
    v_organization_id, p_country_id, p_province_id, p_locality_id, v_neighborhood_id,
    v_street, p_street_number, p_without_number
  )
  on conflict (organization_id) do update set
    country_id = excluded.country_id,
    province_id = excluded.province_id,
    locality_id = excluded.locality_id,
    neighborhood_id = excluded.neighborhood_id,
    street = excluded.street,
    street_number = excluded.street_number,
    without_number = excluded.without_number;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_organization_id,
    auth.uid(),
    'ORGANIZATION_UPDATED',
    'ORGANIZATION',
    v_organization_id,
    jsonb_build_object(
      'sections', jsonb_build_array('identity', 'contact', 'location'),
      'logo_updated', v_logo_path is distinct from v_old_logo_path
    )
  );
end;
$_$;


ALTER FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) IS 'Actualiza de forma transaccional los datos no administrativos y el domicilio de la organización OWNER autenticada.';



CREATE OR REPLACE FUNCTION "public"."validate_desktop_hardware_values"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid; v_type text; v_processor_brand uuid; v_processor_model uuid;
begin
  select d.organization_id,t.name into v_org,v_type from public.customer_devices d join public.device_types t on t.id=d.type_id where d.id=new.customer_device_id;
  if v_type is distinct from 'PC' then return null; end if;
  select nullif(value_text,'')::uuid into v_processor_brand from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_brand_id';
  select nullif(value_text,'')::uuid into v_processor_model from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_model_id';
  if v_processor_model is not null and not exists (select 1 from public.hardware_catalog_models m where m.id=v_processor_model and m.kind='PROCESSOR' and m.brand_id=v_processor_brand and m.is_active and (m.organization_id is null or m.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_MODEL'; end if;
  if v_processor_brand is not null and not exists (select 1 from public.hardware_catalog_brands b where b.id=v_processor_brand and b.kind='PROCESSOR' and b.is_active and (b.organization_id is null or b.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_BRAND'; end if;
  return null;
end; $$;


ALTER FUNCTION "public"."validate_desktop_hardware_values"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_deletion_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subject_type" "text" NOT NULL,
    "organization_id" "uuid",
    "target_user_id" "uuid",
    "requested_by" "uuid",
    "reason" "text" NOT NULL,
    "status" "text" DEFAULT 'PENDING'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "scheduled_for" timestamp with time zone DEFAULT ("now"() + '30 days'::interval) NOT NULL,
    "cancelled_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "auth_cleanup_completed" boolean DEFAULT false NOT NULL,
    CONSTRAINT "account_deletion_requests_reason_check" CHECK ((("char_length"(TRIM(BOTH FROM "reason")) >= 3) AND ("char_length"(TRIM(BOTH FROM "reason")) <= 300))),
    CONSTRAINT "account_deletion_requests_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'CANCELLED'::"text", 'COMPLETED'::"text"]))),
    CONSTRAINT "account_deletion_requests_subject_type_check" CHECK (("subject_type" = ANY (ARRAY['ORGANIZATION'::"text", 'CUSTOMER_ACCOUNT'::"text"]))),
    CONSTRAINT "account_deletion_subject_check" CHECK (((("subject_type" = 'ORGANIZATION'::"text") AND ("organization_id" IS NOT NULL)) OR (("subject_type" = 'CUSTOMER_ACCOUNT'::"text") AND ("target_user_id" IS NOT NULL))))
);


ALTER TABLE "public"."account_deletion_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_deletion_requests" IS 'Solicitudes append-like de baja reversible; el histórico legal permanece en las tablas de negocio y auditoría.';



CREATE TABLE IF NOT EXISTS "public"."audit_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "actor_user_id" "uuid",
    "event_type" "text" NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "uuid",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "result" "text" DEFAULT 'SUCCESS'::"text" NOT NULL,
    CONSTRAINT "audit_events_entity_type_check" CHECK ((("char_length"("entity_type") >= 2) AND ("char_length"("entity_type") <= 80))),
    CONSTRAINT "audit_events_event_type_check" CHECK ((("char_length"("event_type") >= 3) AND ("char_length"("event_type") <= 100))),
    CONSTRAINT "audit_events_result_check" CHECK (("result" = ANY (ARRAY['SUCCESS'::"text", 'FAILURE'::"text"])))
);


ALTER TABLE "public"."audit_events" OWNER TO "postgres";


COMMENT ON COLUMN "public"."audit_events"."result" IS 'Resultado controlado del evento; nunca contiene detalles técnicos ni secretos.';



CREATE TABLE IF NOT EXISTS "public"."auth_rate_limits" (
    "action" "text" NOT NULL,
    "key_hash" "text" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "window_started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "blocked_until" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "auth_rate_limits_attempts_check" CHECK (("attempts" >= 0)),
    CONSTRAINT "auth_rate_limits_key_hash_check" CHECK (("char_length"("key_hash") = 64))
);


ALTER TABLE "public"."auth_rate_limits" OWNER TO "postgres";


COMMENT ON TABLE "public"."auth_rate_limits" IS 'Contadores ef??meros por HMAC; nunca almacena IP ni correo en claro.';



CREATE TABLE IF NOT EXISTS "public"."component_attribute_definitions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "component_type_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "component_attribute_definitions_field_type_check" CHECK (("field_type" = ANY (ARRAY['TEXT'::"text", 'NUMBER'::"text", 'SELECT'::"text"]))),
    CONSTRAINT "component_attribute_definitions_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text"))
);


ALTER TABLE "public"."component_attribute_definitions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_attribute_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attribute_definition_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."component_attribute_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "max_instances" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."component_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."countries" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "countries_id_check" CHECK (("id" ~ '^[A-Z]{2}$'::"text")),
    CONSTRAINT "countries_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 100)))
);


ALTER TABLE "public"."countries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_field_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_device_id" "uuid" NOT NULL,
    "device_type_field_id" "uuid" NOT NULL,
    "option_id" "uuid",
    "value_text" "text",
    "value_number" numeric,
    "value_boolean" boolean,
    "value_json" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_device_field_values_check" CHECK (("num_nonnulls"("value_text", "value_number", "value_boolean", "value_json", "option_id") = 1))
);


ALTER TABLE "public"."customer_device_field_values" OWNER TO "postgres";


COMMENT ON TABLE "public"."customer_device_field_values" IS 'Valores configurables de un dispositivo. Los catálogos maestros se conservan en tablas normalizadas.';



CREATE TABLE IF NOT EXISTS "public"."customer_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "type_id" "uuid" NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "model" "text",
    "year" smallint,
    "color" "text",
    "serial_number" "text",
    "imei_1" "text",
    "imei_2" "text",
    "attributes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "memory_modules" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "storage_units" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "accessories" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "model_id" "uuid",
    "family_id" "uuid",
    "variant_id" "uuid",
    "color_id" "uuid",
    "operating_system_id" "uuid",
    "mobile_operator_id" "uuid",
    "is_locked" boolean DEFAULT false NOT NULL,
    "lock_type_id" "uuid",
    CONSTRAINT "customer_devices_color_check" CHECK ((("color" IS NULL) OR ("char_length"("color") <= 80))),
    CONSTRAINT "customer_devices_imei_1_check" CHECK ((("imei_1" IS NULL) OR ("imei_1" ~ '^[0-9]{0,20}$'::"text"))),
    CONSTRAINT "customer_devices_imei_2_check" CHECK ((("imei_2" IS NULL) OR ("imei_2" ~ '^[0-9]{0,20}$'::"text"))),
    CONSTRAINT "customer_devices_model_check" CHECK ((("char_length"(TRIM(BOTH FROM "model")) >= 2) AND ("char_length"(TRIM(BOTH FROM "model")) <= 120))),
    CONSTRAINT "customer_devices_serial_number_check" CHECK ((("serial_number" IS NULL) OR ("char_length"("serial_number") <= 120))),
    CONSTRAINT "customer_devices_year_check" CHECK ((("year" >= 1950) AND ("year" <= 2200)))
);


ALTER TABLE "public"."customer_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_user_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "auth_user_id" "uuid" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."customer_user_links" OWNER TO "postgres";


COMMENT ON TABLE "public"."customer_user_links" IS 'V??nculo expl??cito y opcional entre un cliente del negocio y una identidad de Auth.';



CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "contact_email" "text",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "portal_account_deleted_at" timestamp with time zone,
    CONSTRAINT "customers_first_name_check" CHECK ((("char_length"("first_name") >= 1) AND ("char_length"("first_name") <= 80))),
    CONSTRAINT "customers_last_name_check" CHECK ((("char_length"("last_name") >= 1) AND ("char_length"("last_name") <= 80)))
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


COMMENT ON TABLE "public"."customers" IS 'Datos de contacto del cliente; no equivale a una identidad de Auth.';



CREATE TABLE IF NOT EXISTS "public"."device_accessories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_accessories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_field_dependencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_field_id" "uuid" NOT NULL,
    "parent_device_type_field_id" "uuid" NOT NULL,
    "operator" "text" DEFAULT 'EQUALS'::"text" NOT NULL,
    "expected_value" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_field_dependencies_check" CHECK (("device_type_field_id" <> "parent_device_type_field_id")),
    CONSTRAINT "device_field_dependencies_operator_check" CHECK (("operator" = ANY (ARRAY['EQUALS'::"text", 'NOT_EQUALS'::"text", 'IN'::"text", 'NOT_EMPTY'::"text", 'EMPTY'::"text"])))
);


ALTER TABLE "public"."device_field_dependencies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_field_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "field_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_field_options_label_check" CHECK ((("char_length"(TRIM(BOTH FROM "label")) >= 1) AND ("char_length"(TRIM(BOTH FROM "label")) <= 160))),
    CONSTRAINT "device_field_options_value_check" CHECK ((("char_length"(TRIM(BOTH FROM "value")) >= 1) AND ("char_length"(TRIM(BOTH FROM "value")) <= 160)))
);


ALTER TABLE "public"."device_field_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_fields" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "data_source_key" "text",
    "placeholder" "text",
    "help_text" "text",
    "validation" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_fields_data_source_key_check" CHECK ((("data_source_key" IS NULL) OR ("data_source_key" = ANY (ARRAY['brand'::"text", 'family'::"text", 'model'::"text", 'variant'::"text", 'color'::"text", 'memory_capacity'::"text", 'storage_capacity'::"text", 'operating_system'::"text", 'mobile_operator'::"text", 'accessory'::"text", 'lock_type'::"text", 'hardware_processor_brand'::"text", 'hardware_processor_model'::"text", 'hardware_motherboard_brand'::"text", 'hardware_motherboard_model'::"text", 'hardware_gpu_brand'::"text", 'hardware_gpu_model'::"text", 'hardware_power_supply_brand'::"text", 'hardware_power_supply_model'::"text", 'hardware_case_brand'::"text", 'hardware_case_model'::"text", 'hardware_cpu_cooler_brand'::"text", 'hardware_cpu_cooler_model'::"text", 'hardware_wifi_brand'::"text", 'hardware_wifi_model'::"text", 'notebook_keyboard_mount'::"text"])))),
    CONSTRAINT "device_fields_field_type_check" CHECK (("field_type" = ANY (ARRAY['TEXT'::"text", 'NUMBER'::"text", 'TEXTAREA'::"text", 'SELECT'::"text", 'MULTISELECT'::"text", 'CHECKBOX'::"text", 'RADIO'::"text", 'SWITCH'::"text", 'REPEATABLE'::"text"]))),
    CONSTRAINT "device_fields_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_fields_label_check" CHECK ((("char_length"(TRIM(BOTH FROM "label")) >= 2) AND ("char_length"(TRIM(BOTH FROM "label")) <= 120))),
    CONSTRAINT "device_fields_validation_check" CHECK (("jsonb_typeof"("validation") = 'object'::"text"))
);


ALTER TABLE "public"."device_fields" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_fields" IS 'Definición reutilizable de controles dinámicos. Los data_source_key se resuelven con código seguro en servidor; nunca contienen SQL.';



CREATE TABLE IF NOT EXISTS "public"."device_form_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "device_type_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_form_sections_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_form_sections_title_check" CHECK ((("char_length"(TRIM(BOTH FROM "title")) >= 2) AND ("char_length"(TRIM(BOTH FROM "title")) <= 100)))
);


ALTER TABLE "public"."device_form_sections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_lock_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_lock_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_model_variants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "model_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "technical_code" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_model_variants_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 140)))
);


ALTER TABLE "public"."device_model_variants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_product_families" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "brand_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "code" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_product_families_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 120)))
);


ALTER TABLE "public"."device_product_families" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_reception_controls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "applicable_when_attribute" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_reception_controls_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_reception_controls_label_check" CHECK ((("char_length"("btrim"("label")) >= 2) AND ("char_length"("btrim"("label")) <= 120)))
);


ALTER TABLE "public"."device_reception_controls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_receptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "device_id" "uuid" NOT NULL,
    "reported_problem" "text" NOT NULL,
    "observations" "text" DEFAULT ''::"text" NOT NULL,
    "condition_score" numeric(6,1) NOT NULL,
    "calculated_condition" "text" NOT NULL,
    "intake_snapshot" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'CONFIRMED'::"text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_receptions_calculated_condition_check" CHECK (("calculated_condition" = ANY (ARRAY['Excelente estado'::"text", 'Buen estado'::"text", 'Desgaste normal'::"text", 'Estado regular'::"text", 'Dañado'::"text", 'Muy dañado'::"text"]))),
    CONSTRAINT "device_receptions_condition_score_check" CHECK (("condition_score" >= (0)::numeric)),
    CONSTRAINT "device_receptions_observations_check" CHECK (("char_length"("observations") <= 2000)),
    CONSTRAINT "device_receptions_reported_problem_check" CHECK ((("char_length"(TRIM(BOTH FROM "reported_problem")) >= 10) AND ("char_length"(TRIM(BOTH FROM "reported_problem")) <= 2000))),
    CONSTRAINT "device_receptions_status_check" CHECK (("status" = 'CONFIRMED'::"text"))
);


ALTER TABLE "public"."device_receptions" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_receptions" IS 'Snapshot inmutable del estado observado al recibir el equipo; hallazgos posteriores deben registrarse por separado.';



CREATE TABLE IF NOT EXISTS "public"."device_type_diagnostic_tests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "diagnostic_test_type_id" "uuid" NOT NULL,
    "section_id" "uuid",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."device_type_diagnostic_tests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_fields" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "section_id" "uuid" NOT NULL,
    "field_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "overrides" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_type_fields_overrides_check" CHECK (("jsonb_typeof"("overrides") = 'object'::"text"))
);


ALTER TABLE "public"."device_type_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_services" (
    "device_type_id" "uuid" NOT NULL,
    "technical_service_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."device_type_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."diagnostic_result_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."diagnostic_result_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."diagnostic_test_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "category" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."diagnostic_test_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hardware_catalog_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "kind" "text" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hardware_catalog_brands_kind_check" CHECK (("kind" = ANY (ARRAY['PROCESSOR'::"text", 'MOTHERBOARD'::"text", 'GPU'::"text", 'POWER_SUPPLY'::"text", 'CASE'::"text", 'CPU_COOLER'::"text", 'WIFI_ADAPTER'::"text"]))),
    CONSTRAINT "hardware_catalog_brands_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120)))
);


ALTER TABLE "public"."hardware_catalog_brands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_brands_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120)))
);


ALTER TABLE "public"."inventory_brands" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_brands" IS 'Marcas de artículos por organización; se mantiene separado de device_brands para no mezclar repuestos con dispositivos.';



CREATE TABLE IF NOT EXISTS "public"."inventory_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_categories_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 100)))
);


ALTER TABLE "public"."inventory_categories" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_categories" IS 'Catálogo global de categorías genéricas de inventario, de solo lectura para usuarios autenticados.';



CREATE TABLE IF NOT EXISTS "public"."inventory_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "category_id" "uuid" NOT NULL,
    "brand_id" "uuid",
    "preferred_supplier_id" "uuid",
    "sku" "text",
    "normalized_sku" "text" GENERATED ALWAYS AS ("upper"("btrim"("sku"))) STORED,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "description" "text",
    "cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "sale_price" numeric(14,2) DEFAULT 0 NOT NULL,
    "current_stock" numeric(14,3) DEFAULT 0 NOT NULL,
    "minimum_stock" numeric(14,3) DEFAULT 0 NOT NULL,
    "unit" "text" DEFAULT 'UNIT'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_items_cost_check" CHECK (("cost" >= (0)::numeric)),
    CONSTRAINT "inventory_items_current_stock_check" CHECK (("current_stock" >= (0)::numeric)),
    CONSTRAINT "inventory_items_description_check" CHECK ((("description" IS NULL) OR ("char_length"("description") <= 2000))),
    CONSTRAINT "inventory_items_minimum_stock_check" CHECK (("minimum_stock" >= (0)::numeric)),
    CONSTRAINT "inventory_items_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 160))),
    CONSTRAINT "inventory_items_sale_price_check" CHECK (("sale_price" >= (0)::numeric)),
    CONSTRAINT "inventory_items_sku_check" CHECK ((("sku" IS NULL) OR (("char_length"("btrim"("sku")) >= 1) AND ("char_length"("btrim"("sku")) <= 80)))),
    CONSTRAINT "inventory_items_unit_check" CHECK (("unit" ~ '^[A-Z][A-Z0-9_]{0,19}$'::"text"))
);


ALTER TABLE "public"."inventory_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "inventory_item_id" "uuid" NOT NULL,
    "movement_type" "public"."inventory_movement_type" NOT NULL,
    "quantity_delta" numeric(14,3) NOT NULL,
    "stock_before" numeric(14,3) NOT NULL,
    "stock_after" numeric(14,3) NOT NULL,
    "unit_cost" numeric(14,2),
    "reason" "text" NOT NULL,
    "reference_type" "text",
    "reference_id" "uuid",
    "actor_user_id" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_movements_balance_check" CHECK (("stock_after" = ("stock_before" + "quantity_delta"))),
    CONSTRAINT "inventory_movements_delta_type_check" CHECK (((("movement_type" = 'IN'::"public"."inventory_movement_type") AND ("quantity_delta" > (0)::numeric)) OR (("movement_type" = 'OUT'::"public"."inventory_movement_type") AND ("quantity_delta" < (0)::numeric)) OR (("movement_type" = 'ADJUSTMENT'::"public"."inventory_movement_type") AND ("quantity_delta" <> (0)::numeric)))),
    CONSTRAINT "inventory_movements_reason_check" CHECK ((("char_length"("btrim"("reason")) >= 3) AND ("char_length"("btrim"("reason")) <= 500))),
    CONSTRAINT "inventory_movements_reference_pair_check" CHECK (((("reference_type" IS NULL) AND ("reference_id" IS NULL)) OR (("reference_type" IS NOT NULL) AND ("reference_id" IS NOT NULL)))),
    CONSTRAINT "inventory_movements_reference_type_check" CHECK ((("reference_type" IS NULL) OR ("reference_type" ~ '^[A-Z][A-Z0-9_]{1,49}$'::"text"))),
    CONSTRAINT "inventory_movements_stock_after_check" CHECK (("stock_after" >= (0)::numeric)),
    CONSTRAINT "inventory_movements_stock_before_check" CHECK (("stock_before" >= (0)::numeric)),
    CONSTRAINT "inventory_movements_unit_cost_check" CHECK ((("unit_cost" IS NULL) OR ("unit_cost" >= (0)::numeric)))
);


ALTER TABLE "public"."inventory_movements" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_movements" IS 'Historial inmutable y atómico que mantiene sincronizado inventory_items.current_stock.';



CREATE TABLE IF NOT EXISTS "public"."localities" (
    "id" "text" NOT NULL,
    "province_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "localities_id_check" CHECK ((("char_length"("id") >= 1) AND ("char_length"("id") <= 40))),
    CONSTRAINT "localities_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 140)))
);


ALTER TABLE "public"."localities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."memory_capacities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "capacity_mb" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."memory_capacities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mobile_operators" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "country_code" "text" DEFAULT 'AR'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mobile_operators" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."neighborhoods" (
    "id" "text" NOT NULL,
    "locality_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "neighborhoods_id_check" CHECK ((("char_length"("id") >= 1) AND ("char_length"("id") <= 80))),
    CONSTRAINT "neighborhoods_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 140)))
);


ALTER TABLE "public"."neighborhoods" OWNER TO "postgres";


COMMENT ON TABLE "public"."neighborhoods" IS 'Catálogo global de barrios. El conjunto inicial de Formosa capital proviene de bdformostock_schema.sql.';



CREATE TABLE IF NOT EXISTS "public"."notebook_keyboard_mount_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "image_reference" "text",
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notebook_keyboard_mount_types_description_check" CHECK ((("char_length"("btrim"("description")) >= 10) AND ("char_length"("btrim"("description")) <= 1000))),
    CONSTRAINT "notebook_keyboard_mount_types_image_reference_check" CHECK ((("image_reference" IS NULL) OR ("char_length"("btrim"("image_reference")) <= 500))),
    CONSTRAINT "notebook_keyboard_mount_types_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 100)))
);


ALTER TABLE "public"."notebook_keyboard_mount_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."operating_systems" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "platform" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."operating_systems" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organization_addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "country_id" "text" NOT NULL,
    "province_id" "text" NOT NULL,
    "locality_id" "text" NOT NULL,
    "neighborhood_id" "text",
    "street" "text" NOT NULL,
    "street_number" integer,
    "without_number" boolean DEFAULT false NOT NULL,
    "floor" "text",
    "apartment" "text",
    "postal_code" "text",
    "reference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "organization_addresses_apartment_check" CHECK ((("apartment" IS NULL) OR (("char_length"("apartment") <= 10) AND ("apartment" !~ '[<>]'::"text") AND ("apartment" !~ '[[:cntrl:]]'::"text")))),
    CONSTRAINT "organization_addresses_floor_check" CHECK ((("floor" IS NULL) OR (("char_length"("floor") <= 10) AND ("floor" !~ '[<>]'::"text") AND ("floor" !~ '[[:cntrl:]]'::"text")))),
    CONSTRAINT "organization_addresses_number_check" CHECK ((("without_number" AND ("street_number" IS NULL)) OR ((NOT "without_number") AND ("street_number" IS NOT NULL)))),
    CONSTRAINT "organization_addresses_postal_code_check" CHECK ((("postal_code" IS NULL) OR (("char_length"("postal_code") >= 4) AND ("char_length"("postal_code") <= 10)))),
    CONSTRAINT "organization_addresses_reference_check" CHECK ((("reference" IS NULL) OR (("char_length"("reference") <= 200) AND ("reference" !~ '[<>]'::"text") AND ("reference" !~ '[[:cntrl:]]'::"text")))),
    CONSTRAINT "organization_addresses_street_check" CHECK (((("char_length"("street") >= 2) AND ("char_length"("street") <= 120)) AND ("street" !~ '[<>]'::"text") AND ("street" !~ '[[:cntrl:]]'::"text"))),
    CONSTRAINT "organization_addresses_street_number_check" CHECK ((("street_number" >= 1) AND ("street_number" <= 999999)))
);


ALTER TABLE "public"."organization_addresses" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_addresses" IS 'Domicilio principal estructurado. Lectura protegida por RLS; escritura exclusivamente mediante RPC autorizada y auditada.';



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "status" "public"."organization_status" DEFAULT 'ACTIVE'::"public"."organization_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "trade_name" "text",
    "logo_path" "text",
    "phone" "text",
    "contact_email" "text",
    "address" "text",
    "locality" "text",
    "province" "text",
    "description" "text",
    "initial_setup_completed" boolean DEFAULT false NOT NULL,
    "initial_setup_step" smallint DEFAULT 1 NOT NULL,
    "phone_country_code" "text",
    "phone_calling_code" "text",
    "phone_national_number" "text",
    CONSTRAINT "organizations_initial_setup_step_check" CHECK ((("initial_setup_step" >= 1) AND ("initial_setup_step" <= 4))),
    CONSTRAINT "organizations_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 120))),
    CONSTRAINT "organizations_name_format_check" CHECK (((("char_length"("name") >= 2) AND ("char_length"("name") <= 120)) AND ("name" !~ '[<>]'::"text") AND ("name" !~ '[[:cntrl:]]'::"text"))),
    CONSTRAINT "organizations_phone_components_check" CHECK (((("phone_country_code" IS NULL) AND ("phone_calling_code" IS NULL) AND ("phone_national_number" IS NULL)) OR (("phone_country_code" ~ '^[A-Z]{2}$'::"text") AND ("phone_calling_code" ~ '^\+[1-9][0-9]{0,3}$'::"text") AND ("phone_national_number" ~ '^[0-9]{4,15}$'::"text") AND ("phone" = ("phone_calling_code" || "phone_national_number"))))),
    CONSTRAINT "organizations_setup_fields_length" CHECK (((("trade_name" IS NULL) OR (("char_length"("trade_name") >= 2) AND ("char_length"("trade_name") <= 120))) AND (("logo_path" IS NULL) OR ("char_length"("logo_path") <= 500)) AND (("phone" IS NULL) OR (("char_length"("phone") >= 6) AND ("char_length"("phone") <= 30))) AND (("contact_email" IS NULL) OR ("char_length"("contact_email") <= 254)) AND (("address" IS NULL) OR (("char_length"("address") >= 3) AND ("char_length"("address") <= 180))) AND (("locality" IS NULL) OR (("char_length"("locality") >= 2) AND ("char_length"("locality") <= 100))) AND (("province" IS NULL) OR (("char_length"("province") >= 2) AND ("char_length"("province") <= 100))) AND (("description" IS NULL) OR (("char_length"("description") >= 10) AND ("char_length"("description") <= 600))))),
    CONSTRAINT "organizations_slug_check" CHECK (((("char_length"("slug") >= 2) AND ("char_length"("slug") <= 80)) AND ("slug" ~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$'::"text")))
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."organizations"."logo_path" IS 'Ruta privada dentro del bucket organization-logos; nunca almacena el archivo ni una URL firmada.';



COMMENT ON COLUMN "public"."organizations"."phone" IS 'Teléfono E.164 normalizado de contacto del negocio.';



COMMENT ON COLUMN "public"."organizations"."initial_setup_completed" IS 'Bloquea la operación hasta que el OWNER completa los datos fundamentales.';



COMMENT ON COLUMN "public"."organizations"."initial_setup_step" IS 'Próximo paso pendiente del onboarding; no reemplaza initial_setup_completed.';



COMMENT ON COLUMN "public"."organizations"."phone_country_code" IS 'Código ISO 3166-1 alpha-2 derivado y validado en servidor.';



COMMENT ON COLUMN "public"."organizations"."phone_calling_code" IS 'Prefijo telefónico internacional con signo +.';



COMMENT ON COLUMN "public"."organizations"."phone_national_number" IS 'Número nacional normalizado, sin prefijo internacional.';



CREATE TABLE IF NOT EXISTS "public"."password_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "fingerprint" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "password_history_fingerprint_check" CHECK (("fingerprint" ~ '^[a-f0-9]{64}$'::"text"))
);


ALTER TABLE "public"."password_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."password_history" IS 'Fingerprints HMAC con pepper server-side; nunca contraseñas ni hashes de auth.users.';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "organization_id" "uuid",
    "first_name" "text",
    "last_name" "text",
    "display_name" "text",
    "role" "public"."app_role" DEFAULT 'CUSTOMER'::"public"."app_role" NOT NULL,
    "status" "public"."profile_status" DEFAULT 'ACTIVE'::"public"."profile_status" NOT NULL,
    "must_change_password" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "profiles_names_length" CHECK (((("first_name" IS NULL) OR ("char_length"("first_name") <= 80)) AND (("last_name" IS NULL) OR ("char_length"("last_name") <= 80)) AND (("display_name" IS NULL) OR ("char_length"("display_name") <= 170))))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."provinces" (
    "id" "text" NOT NULL,
    "country_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "provinces_id_check" CHECK ((("char_length"("id") >= 1) AND ("char_length"("id") <= 20))),
    CONSTRAINT "provinces_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 120)))
);


ALTER TABLE "public"."provinces" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_evidence_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."reception_evidence_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_inspection_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "reception_id" "uuid" NOT NULL,
    "item_key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "condition" "text" NOT NULL,
    "severity" numeric(3,1),
    "observation" "text" DEFAULT ''::"text" NOT NULL,
    "is_critical" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reception_inspection_items_condition_check" CHECK (("condition" = ANY (ARRAY['NO_DAMAGE'::"text", 'LIGHT_WEAR'::"text", 'SCRATCHED'::"text", 'DENTED'::"text", 'BROKEN'::"text", 'MISSING'::"text", 'NOT_WORKING'::"text", 'NOT_VERIFIABLE'::"text", 'NOT_APPLICABLE'::"text"]))),
    CONSTRAINT "reception_inspection_items_item_key_check" CHECK (("item_key" ~ '^[a-z0-9_]+$'::"text")),
    CONSTRAINT "reception_inspection_items_label_check" CHECK ((("char_length"("label") >= 2) AND ("char_length"("label") <= 100))),
    CONSTRAINT "reception_inspection_items_observation_check" CHECK (("char_length"("observation") <= 500))
);


ALTER TABLE "public"."reception_inspection_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "reception_id" "uuid" NOT NULL,
    "storage_path" "text" NOT NULL,
    "description" "text",
    "inspection_item_key" "text",
    "uploaded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reception_photos_description_check" CHECK ((("description" IS NULL) OR ("char_length"("description") <= 300))),
    CONSTRAINT "reception_photos_inspection_item_key_check" CHECK ((("inspection_item_key" IS NULL) OR ("inspection_item_key" ~ '^[a-z0-9_]+$'::"text"))),
    CONSTRAINT "reception_photos_storage_path_check" CHECK ((("char_length"("storage_path") >= 10) AND ("char_length"("storage_path") <= 400)))
);


ALTER TABLE "public"."reception_photos" OWNER TO "postgres";


COMMENT ON TABLE "public"."reception_photos" IS 'Metadatos de evidencia privada; el archivo reside en Supabase Storage.';



CREATE TABLE IF NOT EXISTS "public"."repair_device_component_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "component_id" "uuid" NOT NULL,
    "attribute_definition_id" "uuid" NOT NULL,
    "option_id" "uuid",
    "value_text" "text"
);


ALTER TABLE "public"."repair_device_component_values" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."repair_device_components" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_device_id" "uuid" NOT NULL,
    "component_type_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."repair_device_components" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."repair_device_diagnostics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "reception_id" "uuid" NOT NULL,
    "diagnostic_test_type_id" "uuid" NOT NULL,
    "result_type_id" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."repair_device_diagnostics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."service_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."storage_capacities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "capacity_gb" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."storage_capacities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "legal_name" "text",
    "phone" "text",
    "email" "text",
    "website" "text",
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "suppliers_email_check" CHECK ((("email" IS NULL) OR (("char_length"("btrim"("email")) >= 3) AND ("char_length"("btrim"("email")) <= 254)))),
    CONSTRAINT "suppliers_legal_name_check" CHECK ((("legal_name" IS NULL) OR (("char_length"("btrim"("legal_name")) >= 2) AND ("char_length"("btrim"("legal_name")) <= 160)))),
    CONSTRAINT "suppliers_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120))),
    CONSTRAINT "suppliers_notes_check" CHECK ((("notes" IS NULL) OR ("char_length"("notes") <= 2000))),
    CONSTRAINT "suppliers_phone_check" CHECK ((("phone" IS NULL) OR (("char_length"("btrim"("phone")) >= 6) AND ("char_length"("btrim"("phone")) <= 30)))),
    CONSTRAINT "suppliers_website_check" CHECK ((("website" IS NULL) OR (("char_length"("btrim"("website")) >= 8) AND ("char_length"("btrim"("website")) <= 500))))
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."technical_services" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "service_category_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."technical_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_quick_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "service" "text" NOT NULL,
    "url" "text" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_quick_links_service_check" CHECK (("service" = ANY (ARRAY['GOOGLE'::"text", 'GMAIL'::"text", 'YOUTUBE'::"text", 'WHATSAPP'::"text", 'FACEBOOK'::"text", 'INSTAGRAM'::"text", 'TELEGRAM'::"text"]))),
    CONSTRAINT "user_quick_links_url_allowed" CHECK ("public"."quick_link_url_allowed"("service", "url")),
    CONSTRAINT "user_quick_links_url_check" CHECK ((("char_length"("url") >= 12) AND ("char_length"("url") <= 2048)))
);


ALTER TABLE "public"."user_quick_links" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_quick_links" IS 'Enlaces personales configurables; cada identidad accede exclusivamente a sus propios registros.';



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_rate_limits"
    ADD CONSTRAINT "auth_rate_limits_pkey" PRIMARY KEY ("action", "key_hash");



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_component_type_id_key_key" UNIQUE ("component_type_id", "key");



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_attribute_definition_id_value_key" UNIQUE ("attribute_definition_id", "value");



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."countries"
    ADD CONSTRAINT "countries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_customer_device_id_device_type_key" UNIQUE ("customer_device_id", "device_type_field_id");



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_customer_id_auth_user_id_key" UNIQUE ("customer_id", "auth_user_id");



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "device_accessories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "device_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "device_colors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "device_field_dependencies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "device_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_lock_types"
    ADD CONSTRAINT "device_lock_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "device_reception_controls_device_type_id_key_key" UNIQUE ("device_type_id", "key");



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "device_reception_controls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_device_type_id_diagnostic_test_key" UNIQUE ("device_type_id", "diagnostic_test_type_id");



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_device_type_id_section_id_field_id_key" UNIQUE ("device_type_id", "section_id", "field_id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_pkey" PRIMARY KEY ("device_type_id", "technical_service_id");



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "device_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."diagnostic_result_types"
    ADD CONSTRAINT "diagnostic_result_types_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."diagnostic_result_types"
    ADD CONSTRAINT "diagnostic_result_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hardware_catalog_brands"
    ADD CONSTRAINT "hardware_catalog_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_id_kind_brand_id_key" UNIQUE ("id", "kind", "brand_id");



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_organization_id_normalized_name_key" UNIQUE ("organization_id", "normalized_name");



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "inventory_categories_normalized_name_key" UNIQUE ("normalized_name");



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "inventory_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."localities"
    ADD CONSTRAINT "localities_id_province_id_key" UNIQUE ("id", "province_id");



ALTER TABLE ONLY "public"."localities"
    ADD CONSTRAINT "localities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."memory_capacities"
    ADD CONSTRAINT "memory_capacities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mobile_operators"
    ADD CONSTRAINT "mobile_operators_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_id_locality_id_key" UNIQUE ("id", "locality_id");



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notebook_keyboard_mount_types"
    ADD CONSTRAINT "notebook_keyboard_mount_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."operating_systems"
    ADD CONSTRAINT "operating_systems_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_organization_id_key" UNIQUE ("organization_id");



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."password_history"
    ADD CONSTRAINT "password_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_id_country_id_key" UNIQUE ("id", "country_id");



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_reception_id_item_key_key" UNIQUE ("reception_id", "item_key");



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_storage_path_key" UNIQUE ("storage_path");



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_value_component_id_attribute_defini_key" UNIQUE ("component_id", "attribute_definition_id");



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_reception_id_diagnostic_test_type_key" UNIQUE ("reception_id", "diagnostic_test_type_id");



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_user_id_service_key" UNIQUE ("user_id", "service");



CREATE INDEX "account_deletion_due_idx" ON "public"."account_deletion_requests" USING "btree" ("scheduled_for") WHERE ("status" = 'PENDING'::"text");



CREATE UNIQUE INDEX "account_deletion_pending_organization_unique" ON "public"."account_deletion_requests" USING "btree" ("organization_id") WHERE (("subject_type" = 'ORGANIZATION'::"text") AND ("status" = 'PENDING'::"text"));



CREATE UNIQUE INDEX "account_deletion_pending_user_unique" ON "public"."account_deletion_requests" USING "btree" ("target_user_id") WHERE (("subject_type" = 'CUSTOMER_ACCOUNT'::"text") AND ("status" = 'PENDING'::"text"));



CREATE INDEX "audit_events_actor_created_idx" ON "public"."audit_events" USING "btree" ("actor_user_id", "created_at" DESC);



CREATE INDEX "audit_events_created_idx" ON "public"."audit_events" USING "btree" ("created_at" DESC);



CREATE INDEX "audit_events_organization_created_idx" ON "public"."audit_events" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "audit_events_result_created_idx" ON "public"."audit_events" USING "btree" ("result", "created_at" DESC);



CREATE INDEX "audit_events_type_created_idx" ON "public"."audit_events" USING "btree" ("event_type", "created_at" DESC);



CREATE INDEX "auth_rate_limits_updated_idx" ON "public"."auth_rate_limits" USING "btree" ("updated_at");



CREATE UNIQUE INDEX "component_types_global_unique" ON "public"."component_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "component_types_org_unique" ON "public"."component_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "countries_normalized_name_key" ON "public"."countries" USING "btree" ("normalized_name");



CREATE INDEX "customer_device_field_values_device_idx" ON "public"."customer_device_field_values" USING "btree" ("organization_id", "customer_device_id");



CREATE INDEX "customer_devices_customer_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "customer_id");



CREATE INDEX "customer_devices_family_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "family_id");



CREATE INDEX "customer_devices_model_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "model_id");



CREATE INDEX "customer_devices_organization_created_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "customer_devices_organization_type_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "type_id");



COMMENT ON INDEX "public"."customer_devices_organization_type_idx" IS 'Acelera consultas de tipos de equipo por organización.';



CREATE INDEX "customer_user_links_organization_idx" ON "public"."customer_user_links" USING "btree" ("organization_id");



CREATE INDEX "customer_user_links_user_idx" ON "public"."customer_user_links" USING "btree" ("auth_user_id");



CREATE UNIQUE INDEX "customers_organization_email_unique" ON "public"."customers" USING "btree" ("organization_id", "lower"("contact_email")) WHERE (("contact_email" IS NOT NULL) AND ("contact_email" <> ''::"text"));



CREATE INDEX "customers_organization_idx" ON "public"."customers" USING "btree" ("organization_id");



CREATE UNIQUE INDEX "customers_organization_phone_unique" ON "public"."customers" USING "btree" ("organization_id", "phone") WHERE (("phone" IS NOT NULL) AND ("phone" <> ''::"text"));



CREATE UNIQUE INDEX "device_accessories_global_unique" ON "public"."device_accessories" USING "btree" ("lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_accessories_org_unique" ON "public"."device_accessories" USING "btree" ("organization_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_brands_global_name_unique" ON "public"."device_brands" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_brands_organization_name_unique" ON "public"."device_brands" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_colors_organization_name_unique" ON "public"."device_colors" USING "btree" ("organization_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_colors_system_name_unique" ON "public"."device_colors" USING "btree" ("lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE INDEX "device_field_dependencies_child_idx" ON "public"."device_field_dependencies" USING "btree" ("device_type_field_id");



CREATE INDEX "device_field_dependencies_parent_idx" ON "public"."device_field_dependencies" USING "btree" ("parent_device_type_field_id");



CREATE INDEX "device_field_options_field_idx" ON "public"."device_field_options" USING "btree" ("field_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "device_field_options_global_unique" ON "public"."device_field_options" USING "btree" ("field_id", "lower"("regexp_replace"(TRIM(BOTH FROM "value"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_field_options_org_unique" ON "public"."device_field_options" USING "btree" ("organization_id", "field_id", "lower"("regexp_replace"(TRIM(BOTH FROM "value"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_fields_global_key_unique" ON "public"."device_fields" USING "btree" ("key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_fields_org_key_unique" ON "public"."device_fields" USING "btree" ("organization_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_form_sections_global_unique" ON "public"."device_form_sections" USING "btree" ("device_type_id", "key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_form_sections_org_unique" ON "public"."device_form_sections" USING "btree" ("organization_id", "device_type_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "device_form_sections_type_idx" ON "public"."device_form_sections" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "device_lock_types_global_unique" ON "public"."device_lock_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_lock_types_org_unique" ON "public"."device_lock_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_model_variants_global_unique" ON "public"."device_model_variants" USING "btree" ("model_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE INDEX "device_model_variants_model_idx" ON "public"."device_model_variants" USING "btree" ("model_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "device_model_variants_org_unique" ON "public"."device_model_variants" USING "btree" ("organization_id", "model_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "device_models_family_idx" ON "public"."device_models" USING "btree" ("family_id") WHERE "is_active";



CREATE INDEX "device_models_lookup_idx" ON "public"."device_models" USING "btree" ("device_type_id", "brand_id", "organization_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "device_models_organization_unique" ON "public"."device_models" USING "btree" ("organization_id", "device_type_id", "brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_models_system_unique" ON "public"."device_models" USING "btree" ("device_type_id", "brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE INDEX "device_product_families_brand_idx" ON "public"."device_product_families" USING "btree" ("brand_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "device_product_families_global_unique" ON "public"."device_product_families" USING "btree" ("brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_product_families_org_unique" ON "public"."device_product_families" USING "btree" ("organization_id", "brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "device_reception_controls_type_idx" ON "public"."device_reception_controls" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE INDEX "device_receptions_device_idx" ON "public"."device_receptions" USING "btree" ("organization_id", "device_id");



CREATE INDEX "device_receptions_organization_created_idx" ON "public"."device_receptions" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "device_type_diagnostic_tests_type_idx" ON "public"."device_type_diagnostic_tests" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE INDEX "device_type_fields_field_idx" ON "public"."device_type_fields" USING "btree" ("field_id");



CREATE INDEX "device_type_fields_type_section_idx" ON "public"."device_type_fields" USING "btree" ("device_type_id", "section_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "device_types_global_name_unique" ON "public"."device_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_types_organization_name_unique" ON "public"."device_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "diagnostic_test_types_global_key_unique" ON "public"."diagnostic_test_types" USING "btree" ("key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "diagnostic_test_types_org_key_unique" ON "public"."diagnostic_test_types" USING "btree" ("organization_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "hardware_catalog_brands_global_unique" ON "public"."hardware_catalog_brands" USING "btree" ("kind", "normalized_name") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "hardware_catalog_brands_org_unique" ON "public"."hardware_catalog_brands" USING "btree" ("organization_id", "kind", "normalized_name") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "hardware_catalog_brands_read_idx" ON "public"."hardware_catalog_brands" USING "btree" ("kind", "organization_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "hardware_catalog_models_global_unique" ON "public"."hardware_catalog_models" USING "btree" ("kind", "brand_id", "normalized_name") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "hardware_catalog_models_org_unique" ON "public"."hardware_catalog_models" USING "btree" ("organization_id", "kind", "brand_id", "normalized_name") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "hardware_catalog_models_read_idx" ON "public"."hardware_catalog_models" USING "btree" ("kind", "brand_id", "organization_id", "name") WHERE "is_active";



CREATE INDEX "inventory_brands_organization_active_idx" ON "public"."inventory_brands" USING "btree" ("organization_id", "is_active", "name");



CREATE INDEX "inventory_categories_active_name_idx" ON "public"."inventory_categories" USING "btree" ("is_active", "name");



CREATE INDEX "inventory_items_organization_active_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "is_active", "normalized_name");



CREATE INDEX "inventory_items_organization_brand_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "brand_id") WHERE ("brand_id" IS NOT NULL);



CREATE INDEX "inventory_items_organization_category_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "category_id");



CREATE UNIQUE INDEX "inventory_items_organization_sku_key" ON "public"."inventory_items" USING "btree" ("organization_id", "normalized_sku") WHERE ("normalized_sku" IS NOT NULL);



CREATE INDEX "inventory_items_organization_supplier_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "preferred_supplier_id") WHERE ("preferred_supplier_id" IS NOT NULL);



CREATE INDEX "inventory_movements_item_created_idx" ON "public"."inventory_movements" USING "btree" ("inventory_item_id", "created_at" DESC);



CREATE INDEX "inventory_movements_organization_created_idx" ON "public"."inventory_movements" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "localities_province_idx" ON "public"."localities" USING "btree" ("province_id", "name");



CREATE UNIQUE INDEX "localities_province_normalized_name_key" ON "public"."localities" USING "btree" ("province_id", "normalized_name");



CREATE UNIQUE INDEX "memory_capacities_global_unique" ON "public"."memory_capacities" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "memory_capacities_org_unique" ON "public"."memory_capacities" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "mobile_operators_global_unique" ON "public"."mobile_operators" USING "btree" ("lower"("name"), "country_code") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "mobile_operators_org_unique" ON "public"."mobile_operators" USING "btree" ("organization_id", "lower"("name"), "country_code") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "neighborhoods_locality_idx" ON "public"."neighborhoods" USING "btree" ("locality_id", "name");



CREATE UNIQUE INDEX "neighborhoods_locality_normalized_name_key" ON "public"."neighborhoods" USING "btree" ("locality_id", "normalized_name");



CREATE UNIQUE INDEX "notebook_keyboard_mount_types_global_unique" ON "public"."notebook_keyboard_mount_types" USING "btree" ("normalized_name") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "notebook_keyboard_mount_types_org_unique" ON "public"."notebook_keyboard_mount_types" USING "btree" ("organization_id", "normalized_name") WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "operating_systems_global_unique" ON "public"."operating_systems" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "operating_systems_org_unique" ON "public"."operating_systems" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "organizations_name_normalized_key" ON "public"."organizations" USING "btree" ("lower"("regexp_replace"(TRIM(BOTH FROM "name"), '[[:space:]]+'::"text", ' '::"text", 'g'::"text")));



COMMENT ON INDEX "public"."organizations_name_normalized_key" IS 'Impide nombres duplicados ignorando mayúsculas, minúsculas y espacios repetidos.';



CREATE INDEX "password_history_user_created_idx" ON "public"."password_history" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "profiles_organization_idx" ON "public"."profiles" USING "btree" ("organization_id");



CREATE INDEX "provinces_country_idx" ON "public"."provinces" USING "btree" ("country_id", "name");



CREATE UNIQUE INDEX "provinces_country_normalized_name_key" ON "public"."provinces" USING "btree" ("country_id", "normalized_name");



CREATE UNIQUE INDEX "reception_evidence_types_global_unique" ON "public"."reception_evidence_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "reception_evidence_types_org_unique" ON "public"."reception_evidence_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "reception_inspection_reception_idx" ON "public"."reception_inspection_items" USING "btree" ("organization_id", "reception_id");



CREATE INDEX "reception_photos_reception_idx" ON "public"."reception_photos" USING "btree" ("organization_id", "reception_id");



CREATE INDEX "repair_device_components_device_idx" ON "public"."repair_device_components" USING "btree" ("organization_id", "customer_device_id", "component_type_id");



CREATE INDEX "repair_device_diagnostics_reception_idx" ON "public"."repair_device_diagnostics" USING "btree" ("organization_id", "reception_id");



CREATE UNIQUE INDEX "service_categories_global_unique" ON "public"."service_categories" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "service_categories_org_unique" ON "public"."service_categories" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "storage_capacities_global_unique" ON "public"."storage_capacities" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "storage_capacities_org_unique" ON "public"."storage_capacities" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "suppliers_organization_active_idx" ON "public"."suppliers" USING "btree" ("organization_id", "is_active", "normalized_name");



CREATE INDEX "technical_services_category_idx" ON "public"."technical_services" USING "btree" ("service_category_id", "name") WHERE "is_active";



CREATE INDEX "user_quick_links_user_enabled_idx" ON "public"."user_quick_links" USING "btree" ("user_id", "enabled");



CREATE OR REPLACE TRIGGER "customer_device_field_values_updated_at" BEFORE UPDATE ON "public"."customer_device_field_values" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE CONSTRAINT TRIGGER "customer_device_pc_hardware_validation" AFTER INSERT OR UPDATE ON "public"."customer_device_field_values" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."validate_desktop_hardware_values"();



CREATE OR REPLACE TRIGGER "customer_devices_set_updated_at" BEFORE UPDATE ON "public"."customer_devices" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "customers_set_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "device_receptions_immutable" BEFORE DELETE OR UPDATE ON "public"."device_receptions" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_confirmed_reception_mutation"();



CREATE OR REPLACE TRIGGER "inventory_brands_protect_identity" BEFORE UPDATE ON "public"."inventory_brands" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "inventory_brands_set_updated_at" BEFORE UPDATE ON "public"."inventory_brands" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "inventory_items_protect_identity" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "inventory_items_protect_stock" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_stock_direct_change"();



CREATE OR REPLACE TRIGGER "inventory_items_set_updated_at" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "inventory_movements_immutable" BEFORE DELETE OR UPDATE ON "public"."inventory_movements" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_movement_mutation"();



CREATE OR REPLACE TRIGGER "organization_addresses_set_updated_at" BEFORE UPDATE ON "public"."organization_addresses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "organizations_set_updated_at" BEFORE UPDATE ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "profiles_audit_personal_data" AFTER UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."audit_profile_data_change"();



CREATE OR REPLACE TRIGGER "profiles_prevent_privilege_escalation" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_profile_privilege_escalation"();



CREATE OR REPLACE TRIGGER "profiles_set_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "reception_items_immutable" BEFORE DELETE OR UPDATE ON "public"."reception_inspection_items" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_confirmed_reception_mutation"();



CREATE OR REPLACE TRIGGER "suppliers_protect_identity" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "suppliers_set_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "user_quick_links_set_updated_at" BEFORE UPDATE ON "public"."user_quick_links" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_component_type_id_fkey" FOREIGN KEY ("component_type_id") REFERENCES "public"."component_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_attribute_definition_id_fkey" FOREIGN KEY ("attribute_definition_id") REFERENCES "public"."component_attribute_definitions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_customer_device_id_fkey" FOREIGN KEY ("customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_device_type_field_id_fkey" FOREIGN KEY ("device_type_field_id") REFERENCES "public"."device_type_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."device_field_options"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_color_id_fkey" FOREIGN KEY ("color_id") REFERENCES "public"."device_colors"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_customer_id_organization_id_fkey" FOREIGN KEY ("customer_id", "organization_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "public"."device_product_families"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_lock_type_id_fkey" FOREIGN KEY ("lock_type_id") REFERENCES "public"."device_lock_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_mobile_operator_id_fkey" FOREIGN KEY ("mobile_operator_id") REFERENCES "public"."mobile_operators"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_model_id_fkey" FOREIGN KEY ("model_id") REFERENCES "public"."device_models"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_operating_system_id_fkey" FOREIGN KEY ("operating_system_id") REFERENCES "public"."operating_systems"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_type_id_fkey" FOREIGN KEY ("type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."device_model_variants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_customer_id_organization_id_fkey" FOREIGN KEY ("customer_id", "organization_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "device_accessories_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "device_accessories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "device_brands_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "device_brands_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "device_colors_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "device_colors_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "device_field_dependencies_device_type_field_id_fkey" FOREIGN KEY ("device_type_field_id") REFERENCES "public"."device_type_fields"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "device_field_dependencies_parent_device_type_field_id_fkey" FOREIGN KEY ("parent_device_type_field_id") REFERENCES "public"."device_type_fields"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_field_id_fkey" FOREIGN KEY ("field_id") REFERENCES "public"."device_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "device_fields_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "device_fields_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_lock_types"
    ADD CONSTRAINT "device_lock_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_lock_types"
    ADD CONSTRAINT "device_lock_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_model_id_fkey" FOREIGN KEY ("model_id") REFERENCES "public"."device_models"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "public"."device_product_families"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "device_reception_controls_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_customer_id_organization_id_fkey" FOREIGN KEY ("customer_id", "organization_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_device_id_organization_id_fkey" FOREIGN KEY ("device_id", "organization_id") REFERENCES "public"."customer_devices"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_diagnostic_test_type_id_fkey" FOREIGN KEY ("diagnostic_test_type_id") REFERENCES "public"."diagnostic_test_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_section_id_fkey" FOREIGN KEY ("section_id") REFERENCES "public"."device_form_sections"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_field_id_fkey" FOREIGN KEY ("field_id") REFERENCES "public"."device_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_section_id_fkey" FOREIGN KEY ("section_id") REFERENCES "public"."device_form_sections"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_technical_service_id_fkey" FOREIGN KEY ("technical_service_id") REFERENCES "public"."technical_services"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "device_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "device_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hardware_catalog_brands"
    ADD CONSTRAINT "hardware_catalog_brands_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hardware_catalog_brands"
    ADD CONSTRAINT "hardware_catalog_brands_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."hardware_catalog_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_brand_organization_fk" FOREIGN KEY ("brand_id", "organization_id") REFERENCES "public"."inventory_brands"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."inventory_categories"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_supplier_organization_fk" FOREIGN KEY ("preferred_supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_inventory_item_id_organization_id_fkey" FOREIGN KEY ("inventory_item_id", "organization_id") REFERENCES "public"."inventory_items"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."localities"
    ADD CONSTRAINT "localities_province_id_fkey" FOREIGN KEY ("province_id") REFERENCES "public"."provinces"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."memory_capacities"
    ADD CONSTRAINT "memory_capacities_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_capacities"
    ADD CONSTRAINT "memory_capacities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mobile_operators"
    ADD CONSTRAINT "mobile_operators_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mobile_operators"
    ADD CONSTRAINT "mobile_operators_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_locality_id_fkey" FOREIGN KEY ("locality_id") REFERENCES "public"."localities"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."notebook_keyboard_mount_types"
    ADD CONSTRAINT "notebook_keyboard_mount_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notebook_keyboard_mount_types"
    ADD CONSTRAINT "notebook_keyboard_mount_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."operating_systems"
    ADD CONSTRAINT "operating_systems_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."operating_systems"
    ADD CONSTRAINT "operating_systems_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_locality_id_province_id_fkey" FOREIGN KEY ("locality_id", "province_id") REFERENCES "public"."localities"("id", "province_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_neighborhood_id_locality_id_fkey" FOREIGN KEY ("neighborhood_id", "locality_id") REFERENCES "public"."neighborhoods"("id", "locality_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_province_id_country_id_fkey" FOREIGN KEY ("province_id", "country_id") REFERENCES "public"."provinces"("id", "country_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."password_history"
    ADD CONSTRAINT "password_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "public"."countries"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_reception_id_organization_id_fkey" FOREIGN KEY ("reception_id", "organization_id") REFERENCES "public"."device_receptions"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_reception_id_organization_id_fkey" FOREIGN KEY ("reception_id", "organization_id") REFERENCES "public"."device_receptions"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_attribute_definition_id_fkey" FOREIGN KEY ("attribute_definition_id") REFERENCES "public"."component_attribute_definitions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_component_id_fkey" FOREIGN KEY ("component_id") REFERENCES "public"."repair_device_components"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."component_attribute_options"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_component_type_id_fkey" FOREIGN KEY ("component_type_id") REFERENCES "public"."component_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_customer_device_id_fkey" FOREIGN KEY ("customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_diagnostic_test_type_id_fkey" FOREIGN KEY ("diagnostic_test_type_id") REFERENCES "public"."diagnostic_test_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_reception_id_fkey" FOREIGN KEY ("reception_id") REFERENCES "public"."device_receptions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_result_type_id_fkey" FOREIGN KEY ("result_type_id") REFERENCES "public"."diagnostic_result_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_service_category_id_fkey" FOREIGN KEY ("service_category_id") REFERENCES "public"."service_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."account_deletion_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_deletion_requests_self_select" ON "public"."account_deletion_requests" FOR SELECT TO "authenticated" USING ((("target_user_id" = "auth"."uid"()) OR ("requested_by" = "auth"."uid"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("subject_type" = 'ORGANIZATION'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'OWNER'::"public"."app_role") AND ("p"."status" = 'ACTIVE'::"public"."profile_status") AND ("p"."organization_id" = "account_deletion_requests"."organization_id")))))));



ALTER TABLE "public"."audit_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_events_select" ON "public"."audit_events" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role"))));



ALTER TABLE "public"."auth_rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."component_attribute_definitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_attribute_definitions_read" ON "public"."component_attribute_definitions" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."component_attribute_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_attribute_options_read" ON "public"."component_attribute_options" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."component_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_types_read" ON "public"."component_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."countries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "countries_read" ON "public"."countries" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."customer_device_field_values" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_field_values_read" ON "public"."customer_device_field_values" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."customer_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_devices_select" ON "public"."customer_devices" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



CREATE POLICY "customer_links_delete" ON "public"."customer_user_links" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"()));



CREATE POLICY "customer_links_insert" ON "public"."customer_user_links" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"() AND ("created_by" = "auth"."uid"())));



CREATE POLICY "customer_links_select" ON "public"."customer_user_links" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR ("public"."current_organization_is_active"() AND (("auth_user_id" = "auth"."uid"()) OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_setup_completed"())))));



ALTER TABLE "public"."customer_user_links" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers_insert" ON "public"."customers" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"()));



CREATE POLICY "customers_select" ON "public"."customers" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"() AND (("public"."current_app_role"() = 'OWNER'::"public"."app_role") OR (EXISTS ( SELECT 1
   FROM "public"."customer_user_links" "l"
  WHERE (("l"."customer_id" = "customers"."id") AND ("l"."auth_user_id" = "auth"."uid"()))))))));



CREATE POLICY "customers_update" ON "public"."customers" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"())) WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"()));



ALTER TABLE "public"."device_accessories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_accessories_read" ON "public"."device_accessories" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_brands_select" ON "public"."device_brands" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_colors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_colors_read_owner" ON "public"."device_colors" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_field_dependencies" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_field_dependencies_read" ON "public"."device_field_dependencies" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_field_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_field_options_read" ON "public"."device_field_options" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_fields" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_fields_read" ON "public"."device_fields" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_form_sections" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_form_sections_read" ON "public"."device_form_sections" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_lock_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_lock_types_read" ON "public"."device_lock_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_model_variants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_model_variants_read" ON "public"."device_model_variants" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_models" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_models_read_owner" ON "public"."device_models" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_product_families" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_product_families_read" ON "public"."device_product_families" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_reception_controls" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_reception_controls_read" ON "public"."device_reception_controls" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."device_types" "t"
  WHERE (("t"."id" = "device_reception_controls"."device_type_id") AND (("t"."organization_id" IS NULL) OR ("t"."organization_id" = "public"."current_organization_id"()))))));



ALTER TABLE "public"."device_receptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_receptions_select" ON "public"."device_receptions" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."device_type_diagnostic_tests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_diagnostic_tests_read" ON "public"."device_type_diagnostic_tests" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_type_fields" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_fields_read" ON "public"."device_type_fields" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."device_types" "t"
  WHERE (("t"."id" = "device_type_fields"."device_type_id") AND (("t"."organization_id" IS NULL) OR ("t"."organization_id" = "public"."current_organization_id"()))))));



ALTER TABLE "public"."device_type_services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_services_read" ON "public"."device_type_services" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_types_select" ON "public"."device_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."diagnostic_result_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "diagnostic_result_types_read" ON "public"."diagnostic_result_types" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."diagnostic_test_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "diagnostic_test_types_read" ON "public"."diagnostic_test_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."hardware_catalog_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hardware_catalog_brands_read" ON "public"."hardware_catalog_brands" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."hardware_catalog_models" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hardware_catalog_models_read" ON "public"."hardware_catalog_models" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."inventory_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_brands_insert" ON "public"."inventory_brands" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "inventory_brands_select" ON "public"."inventory_brands" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "inventory_brands_update" ON "public"."inventory_brands" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."inventory_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_categories_select" ON "public"."inventory_categories" FOR SELECT TO "authenticated" USING (("is_active" OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role")));



ALTER TABLE "public"."inventory_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_items_insert" ON "public"."inventory_items" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"()) AND ("current_stock" = (0)::numeric)));



CREATE POLICY "inventory_items_select" ON "public"."inventory_items" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "inventory_items_update" ON "public"."inventory_items" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."inventory_movements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_movements_select" ON "public"."inventory_movements" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



ALTER TABLE "public"."localities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "localities_read" ON "public"."localities" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."memory_capacities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memory_capacities_read" ON "public"."memory_capacities" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."mobile_operators" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mobile_operators_read" ON "public"."mobile_operators" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."neighborhoods" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "neighborhoods_read" ON "public"."neighborhoods" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."notebook_keyboard_mount_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notebook_keyboard_mount_types_read" ON "public"."notebook_keyboard_mount_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."operating_systems" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operating_systems_read" ON "public"."operating_systems" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."organization_addresses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organization_addresses_insert" ON "public"."organization_addresses" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."status" = 'ACTIVE'::"public"."profile_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "organization_addresses"."organization_id") AND ("o"."status" = 'ACTIVE'::"public"."organization_status"))))));



CREATE POLICY "organization_addresses_select" ON "public"."organization_addresses" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role"))));



CREATE POLICY "organization_addresses_update" ON "public"."organization_addresses" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."status" = 'ACTIVE'::"public"."profile_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "organization_addresses"."organization_id") AND ("o"."status" = 'ACTIVE'::"public"."organization_status")))))) WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."status" = 'ACTIVE'::"public"."profile_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "organization_addresses"."organization_id") AND ("o"."status" = 'ACTIVE'::"public"."organization_status"))))));



ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organizations_select" ON "public"."organizations" FOR SELECT TO "authenticated" USING ((("id" = "public"."current_organization_id"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role")));



ALTER TABLE "public"."password_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND ("organization_id" = "public"."current_organization_id"()))));



CREATE POLICY "profiles_update_self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."provinces" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "provinces_read" ON "public"."provinces" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."reception_evidence_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_evidence_types_read" ON "public"."reception_evidence_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."reception_inspection_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_items_select" ON "public"."reception_inspection_items" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."reception_photos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_photos_select" ON "public"."reception_photos" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."repair_device_component_values" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "repair_device_component_values_read" ON "public"."repair_device_component_values" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."repair_device_components" "c"
  WHERE (("c"."id" = "repair_device_component_values"."component_id") AND ("c"."organization_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."repair_device_components" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "repair_device_components_read" ON "public"."repair_device_components" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."repair_device_diagnostics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "repair_device_diagnostics_read" ON "public"."repair_device_diagnostics" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."service_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_categories_read" ON "public"."service_categories" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."storage_capacities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storage_capacities_read" ON "public"."storage_capacities" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "suppliers_insert" ON "public"."suppliers" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "suppliers_select" ON "public"."suppliers" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "suppliers_update" ON "public"."suppliers" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."technical_services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "technical_services_read" ON "public"."technical_services" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."user_quick_links" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_quick_links_delete_own" ON "public"."user_quick_links" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_insert_own" ON "public"."user_quick_links" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_select_own" ON "public"."user_quick_links" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_update_own" ON "public"."user_quick_links" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON TYPE "public"."inventory_movement_type" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_inventory_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_inventory_owner"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_reception_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_reception_owner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assert_reception_owner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."audit_profile_data_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."audit_profile_data_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_profile_data_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_my_pending_deletion"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_my_pending_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_my_pending_deletion"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_password_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_password_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_password_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") TO "service_role";



GRANT ALL ON TABLE "public"."device_brands" TO "anon";
GRANT ALL ON TABLE "public"."device_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."device_brands" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_brand"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_brand"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_brand"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."device_colors" TO "anon";
GRANT ALL ON TABLE "public"."device_colors" TO "authenticated";
GRANT ALL ON TABLE "public"."device_colors" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_color"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_color"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_color"("p_name" "text") TO "service_role";



GRANT ALL ON TABLE "public"."device_models" TO "anon";
GRANT ALL ON TABLE "public"."device_models" TO "authenticated";
GRANT ALL ON TABLE "public"."device_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."device_types" TO "anon";
GRANT ALL ON TABLE "public"."device_types" TO "authenticated";
GRANT ALL ON TABLE "public"."device_types" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_type"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_type"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_type"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "service_role";



GRANT ALL ON TABLE "public"."hardware_catalog_models" TO "anon";
GRANT ALL ON TABLE "public"."hardware_catalog_models" TO "authenticated";
GRANT ALL ON TABLE "public"."hardware_catalog_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_app_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_organization_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_organization_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_organization_is_active"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_organization_is_active"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_is_active"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_organization_setup_completed"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_organization_setup_completed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_setup_completed"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_due_account_deletions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_due_account_deletions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_initial_organization_setup"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_initial_organization_setup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."finalize_initial_organization_setup"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_pending_deletion"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_pending_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_pending_deletion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_confirmed_reception_mutation"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_confirmed_reception_mutation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_confirmed_reception_mutation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_inventory_movement_mutation"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_inventory_movement_mutation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_inventory_stock_direct_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_inventory_stock_direct_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_escalation"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_escalation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_escalation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."protect_inventory_record_identity"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."protect_inventory_record_identity"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_organization_deletion"("p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_organization_deletion"("p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_organization_deletion"("p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_desktop_hardware_values"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_desktop_hardware_values"() TO "service_role";



GRANT ALL ON TABLE "public"."account_deletion_requests" TO "service_role";
GRANT SELECT ON TABLE "public"."account_deletion_requests" TO "authenticated";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."audit_events" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."audit_events" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_events" TO "service_role";



GRANT ALL ON TABLE "public"."auth_rate_limits" TO "service_role";



GRANT ALL ON TABLE "public"."component_attribute_definitions" TO "anon";
GRANT ALL ON TABLE "public"."component_attribute_definitions" TO "authenticated";
GRANT ALL ON TABLE "public"."component_attribute_definitions" TO "service_role";



GRANT ALL ON TABLE "public"."component_attribute_options" TO "anon";
GRANT ALL ON TABLE "public"."component_attribute_options" TO "authenticated";
GRANT ALL ON TABLE "public"."component_attribute_options" TO "service_role";



GRANT ALL ON TABLE "public"."component_types" TO "anon";
GRANT ALL ON TABLE "public"."component_types" TO "authenticated";
GRANT ALL ON TABLE "public"."component_types" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."countries" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."countries" TO "authenticated";
GRANT ALL ON TABLE "public"."countries" TO "service_role";



GRANT ALL ON TABLE "public"."customer_device_field_values" TO "anon";
GRANT ALL ON TABLE "public"."customer_device_field_values" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_field_values" TO "service_role";



GRANT ALL ON TABLE "public"."customer_devices" TO "anon";
GRANT ALL ON TABLE "public"."customer_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_devices" TO "service_role";



GRANT ALL ON TABLE "public"."customer_user_links" TO "anon";
GRANT ALL ON TABLE "public"."customer_user_links" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_user_links" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."device_accessories" TO "anon";
GRANT ALL ON TABLE "public"."device_accessories" TO "authenticated";
GRANT ALL ON TABLE "public"."device_accessories" TO "service_role";



GRANT ALL ON TABLE "public"."device_field_dependencies" TO "anon";
GRANT ALL ON TABLE "public"."device_field_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."device_field_dependencies" TO "service_role";



GRANT ALL ON TABLE "public"."device_field_options" TO "anon";
GRANT ALL ON TABLE "public"."device_field_options" TO "authenticated";
GRANT ALL ON TABLE "public"."device_field_options" TO "service_role";



GRANT ALL ON TABLE "public"."device_fields" TO "anon";
GRANT ALL ON TABLE "public"."device_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."device_fields" TO "service_role";



GRANT ALL ON TABLE "public"."device_form_sections" TO "anon";
GRANT ALL ON TABLE "public"."device_form_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."device_form_sections" TO "service_role";



GRANT ALL ON TABLE "public"."device_lock_types" TO "anon";
GRANT ALL ON TABLE "public"."device_lock_types" TO "authenticated";
GRANT ALL ON TABLE "public"."device_lock_types" TO "service_role";



GRANT ALL ON TABLE "public"."device_model_variants" TO "anon";
GRANT ALL ON TABLE "public"."device_model_variants" TO "authenticated";
GRANT ALL ON TABLE "public"."device_model_variants" TO "service_role";



GRANT ALL ON TABLE "public"."device_product_families" TO "anon";
GRANT ALL ON TABLE "public"."device_product_families" TO "authenticated";
GRANT ALL ON TABLE "public"."device_product_families" TO "service_role";



GRANT ALL ON TABLE "public"."device_reception_controls" TO "anon";
GRANT ALL ON TABLE "public"."device_reception_controls" TO "authenticated";
GRANT ALL ON TABLE "public"."device_reception_controls" TO "service_role";



GRANT ALL ON TABLE "public"."device_receptions" TO "anon";
GRANT ALL ON TABLE "public"."device_receptions" TO "authenticated";
GRANT ALL ON TABLE "public"."device_receptions" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "anon";
GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_fields" TO "anon";
GRANT ALL ON TABLE "public"."device_type_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_fields" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_services" TO "anon";
GRANT ALL ON TABLE "public"."device_type_services" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_services" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "anon";
GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "anon";
GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "service_role";



GRANT ALL ON TABLE "public"."hardware_catalog_brands" TO "anon";
GRANT ALL ON TABLE "public"."hardware_catalog_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."hardware_catalog_brands" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_brands" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_brands" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_categories" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_items" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_items" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_items" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_movements" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_movements" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."localities" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."localities" TO "authenticated";
GRANT ALL ON TABLE "public"."localities" TO "service_role";



GRANT ALL ON TABLE "public"."memory_capacities" TO "anon";
GRANT ALL ON TABLE "public"."memory_capacities" TO "authenticated";
GRANT ALL ON TABLE "public"."memory_capacities" TO "service_role";



GRANT ALL ON TABLE "public"."mobile_operators" TO "anon";
GRANT ALL ON TABLE "public"."mobile_operators" TO "authenticated";
GRANT ALL ON TABLE "public"."mobile_operators" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."neighborhoods" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."neighborhoods" TO "authenticated";
GRANT ALL ON TABLE "public"."neighborhoods" TO "service_role";



GRANT ALL ON TABLE "public"."notebook_keyboard_mount_types" TO "anon";
GRANT ALL ON TABLE "public"."notebook_keyboard_mount_types" TO "authenticated";
GRANT ALL ON TABLE "public"."notebook_keyboard_mount_types" TO "service_role";



GRANT ALL ON TABLE "public"."operating_systems" TO "anon";
GRANT ALL ON TABLE "public"."operating_systems" TO "authenticated";
GRANT ALL ON TABLE "public"."operating_systems" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organization_addresses" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organization_addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_addresses" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."password_history" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."provinces" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."provinces" TO "authenticated";
GRANT ALL ON TABLE "public"."provinces" TO "service_role";



GRANT ALL ON TABLE "public"."reception_evidence_types" TO "anon";
GRANT ALL ON TABLE "public"."reception_evidence_types" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_evidence_types" TO "service_role";



GRANT ALL ON TABLE "public"."reception_inspection_items" TO "anon";
GRANT ALL ON TABLE "public"."reception_inspection_items" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_inspection_items" TO "service_role";



GRANT ALL ON TABLE "public"."reception_photos" TO "anon";
GRANT ALL ON TABLE "public"."reception_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_photos" TO "service_role";



GRANT ALL ON TABLE "public"."repair_device_component_values" TO "anon";
GRANT ALL ON TABLE "public"."repair_device_component_values" TO "authenticated";
GRANT ALL ON TABLE "public"."repair_device_component_values" TO "service_role";



GRANT ALL ON TABLE "public"."repair_device_components" TO "anon";
GRANT ALL ON TABLE "public"."repair_device_components" TO "authenticated";
GRANT ALL ON TABLE "public"."repair_device_components" TO "service_role";



GRANT ALL ON TABLE "public"."repair_device_diagnostics" TO "anon";
GRANT ALL ON TABLE "public"."repair_device_diagnostics" TO "authenticated";
GRANT ALL ON TABLE "public"."repair_device_diagnostics" TO "service_role";



GRANT ALL ON TABLE "public"."service_categories" TO "anon";
GRANT ALL ON TABLE "public"."service_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."service_categories" TO "service_role";



GRANT ALL ON TABLE "public"."storage_capacities" TO "anon";
GRANT ALL ON TABLE "public"."storage_capacities" TO "authenticated";
GRANT ALL ON TABLE "public"."storage_capacities" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."suppliers" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."technical_services" TO "anon";
GRANT ALL ON TABLE "public"."technical_services" TO "authenticated";
GRANT ALL ON TABLE "public"."technical_services" TO "service_role";



GRANT ALL ON TABLE "public"."user_quick_links" TO "anon";
GRANT ALL ON TABLE "public"."user_quick_links" TO "authenticated";
GRANT ALL ON TABLE "public"."user_quick_links" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";










SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."app_role" AS ENUM (
    'SUPERADMIN',
    'OWNER',
    'CUSTOMER',
    'TECHNICIAN'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE TYPE "public"."inventory_movement_type" AS ENUM (
    'IN',
    'OUT',
    'ADJUSTMENT'
);


ALTER TYPE "public"."inventory_movement_type" OWNER TO "postgres";


CREATE TYPE "public"."organization_status" AS ENUM (
    'ACTIVE',
    'SUSPENDED'
);


ALTER TYPE "public"."organization_status" OWNER TO "postgres";


CREATE TYPE "public"."profile_status" AS ENUM (
    'ACTIVE',
    'SUSPENDED',
    'DISABLED'
);


ALTER TYPE "public"."profile_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid" DEFAULT NULL::"uuid", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_id uuid;
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (p_organization_id, auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_inventory_owner"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_organization_id uuid := public.current_organization_id();
begin
  if v_organization_id is null
    or not public.has_inventory_owner_access(v_organization_id)
  then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return v_organization_id;
end;
$$;


ALTER FUNCTION "public"."assert_inventory_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assert_reception_owner"() RETURNS "uuid"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid;
begin
 select p.organization_id into v_org from public.profiles p join public.organizations o on o.id=p.organization_id where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and o.status='ACTIVE' and o.initial_setup_completed;
 if v_org is null then raise exception 'FORBIDDEN'; end if; return v_org;
end; $$;


ALTER FUNCTION "public"."assert_reception_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_profile_data_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if old.first_name is distinct from new.first_name or old.last_name is distinct from new.last_name or old.display_name is distinct from new.display_name then
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (new.organization_id, auth.uid(), 'PROFILE_UPDATED', 'PROFILE', new.id, jsonb_build_object('personal_data', true));
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."audit_profile_data_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_my_pending_deletion"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_request public.account_deletion_requests%rowtype;
begin
  select * into v_request
  from public.account_deletion_requests
  where status = 'PENDING' and (
    target_user_id = auth.uid()
    or requested_by = auth.uid()
    or (subject_type='ORGANIZATION' and exists (
      select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=account_deletion_requests.organization_id
    ))
  )
  order by requested_at desc limit 1 for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if v_request.scheduled_for <= now() then raise exception 'RECOVERY_PERIOD_EXPIRED'; end if;

  if v_request.subject_type = 'ORGANIZATION' then
    update public.organizations set status = 'ACTIVE' where id = v_request.organization_id and status = 'SUSPENDED';
  else
    update public.profiles set status = 'ACTIVE' where id = auth.uid() and status = 'SUSPENDED';
  end if;
  update public.account_deletion_requests set status = 'CANCELLED', cancelled_at = now() where id = v_request.id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_request.organization_id, auth.uid(), v_request.subject_type || '_DELETION_CANCELLED', v_request.subject_type,
    coalesce(v_request.organization_id, auth.uid()), jsonb_build_object('request_id', v_request.id, 'status', 'CANCELLED'));
  return jsonb_build_object('ok', true, 'subjectType', v_request.subject_type);
end;
$$;


ALTER FUNCTION "public"."cancel_my_pending_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_password_change"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set must_change_password = false where id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."complete_password_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'RECEPTION_CONFIRMED','DEVICE_RECEPTION',v_id,jsonb_build_object('device_id',p_device_id,'condition',v_condition)); return v_id; end; $$;


ALTER FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") RETURNS TABLE("allowed" boolean, "retry_after_seconds" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."device_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "categories" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_brands_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 80)))
);


ALTER TABLE "public"."device_brands" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_custom_device_brand"("p_name" "text") RETURNS SETOF "public"."device_brands"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_BRAND'; end if;
 if exists(select 1 from public.device_brands where (organization_id is null or organization_id=v_org) and lower(name)=lower(v_name)) then raise exception 'DEVICE_BRAND_EXISTS'; end if;
 insert into public.device_brands(organization_id,name,created_by) values(v_org,v_name,auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_BRAND_CREATED','DEVICE_BRAND',v_id,'{}'); return query select * from public.device_brands where id=v_id; end; $$;


ALTER FUNCTION "public"."create_custom_device_brand"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") RETURNS SETOF "public"."device_brands"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_colors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_colors_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 80)))
);


ALTER TABLE "public"."device_colors" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_custom_device_color"("p_name" "text") RETURNS SETOF "public"."device_colors"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin
 if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_COLOR'; end if;
 if exists(select 1 from public.device_colors where (organization_id is null or organization_id=v_org) and lower(regexp_replace(trim(name),'\s+',' ','g'))=lower(v_name)) then raise exception 'DEVICE_COLOR_EXISTS'; end if;
 insert into public.device_colors(organization_id,name,created_by) values(v_org,v_name,auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_COLOR_CREATED','DEVICE_COLOR',v_id,'{}');
 return query select * from public.device_colors where id=v_id;
end; $$;


ALTER FUNCTION "public"."create_custom_device_color"("p_name" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "device_type_id" "uuid" NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "family_id" "uuid",
    "technical_code" "text",
    CONSTRAINT "device_models_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 120)))
);


ALTER TABLE "public"."device_models" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_models" IS 'Catálogo de modelos base o privados por organización; la fuente se deriva de organization_id nulo o no nulo.';



CREATE OR REPLACE FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") RETURNS SETOF "public"."device_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "attribute_group" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_types_attribute_group_check" CHECK (("attribute_group" = ANY (ARRAY['MOBILE'::"text", 'COMPUTER'::"text", 'PRINTER'::"text", 'DISPLAY'::"text", 'NETWORK'::"text", 'GAMING'::"text", 'CAMERA'::"text", 'STORAGE'::"text", 'AUDIO'::"text", 'PERIPHERAL'::"text", 'POWER'::"text", 'COMMERCIAL'::"text", 'OTHER'::"text"]))),
    CONSTRAINT "device_types_category_check" CHECK ((("char_length"("category") >= 2) AND ("char_length"("category") <= 80))),
    CONSTRAINT "device_types_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 80)))
);


ALTER TABLE "public"."device_types" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_types" IS 'Tipos globales y por organización. Los duplicados se desactivan para nuevas altas; nunca se borran si pueden estar referenciados históricamente.';



CREATE OR REPLACE FUNCTION "public"."create_custom_device_type"("p_name" "text") RETURNS SETOF "public"."device_types"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_TYPE'; end if;
 if exists(select 1 from public.device_types where (organization_id is null or organization_id=v_org) and lower(name)=lower(v_name)) then raise exception 'DEVICE_TYPE_EXISTS'; end if;
 insert into public.device_types(organization_id,name,category,attribute_group,created_by) values(v_org,v_name,'Personalizados','OTHER',auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_TYPE_CREATED','DEVICE_TYPE',v_id,'{}'); return query select * from public.device_types where id=v_id; end; $$;


ALTER FUNCTION "public"."create_custom_device_type"("p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin
 perform 1 from public.customers where id=p_customer_id and organization_id=v_org; if not found then raise exception 'INVALID_CUSTOMER'; end if;
 perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
 perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org); if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
 insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
 values(v_org,p_customer_id,p_type_id,p_brand_id,regexp_replace(trim(p_model),'\s+',' ','g'),nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),nullif(trim(p_imei_1),''),nullif(trim(p_imei_2),''),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_id,jsonb_build_object('customer_id',p_customer_id)); return v_id; end; $$;


ALTER FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_device_id uuid; v_is_pc boolean; v_is_notebook boolean; v_model text:=regexp_replace(btrim(coalesce(p_model,'')),'[[:space:]]+',' ','g'); v_attributes jsonb;
begin
  select name='PC',name='Notebook' into v_is_pc,v_is_notebook from public.device_types where id=p_type_id;
  if not coalesce(v_is_pc,false) and char_length(v_model) < 2 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into v_attributes from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) where nullif(regexp_replace(trim(value #>> '{}'),'[[:space:]]+',' ','g'),'') is not null;
  v_device_id:=public.create_customer_device_dynamic_legacy(p_customer_id,p_type_id,p_brand_id,p_model_id,case when coalesce(v_is_pc,false) and v_model='' then '__unknown__' else v_model end,p_year,p_color,p_serial_number,p_imei_1,p_imei_2,v_attributes,p_memories,p_storage_units,p_accessories);
  update public.customer_devices set model=case when coalesce(v_is_pc,false) and v_model='' then null else model end, memory_modules=case when coalesce(v_is_notebook,false) and coalesce(jsonb_array_length(p_memories),0)=0 then null else memory_modules end, storage_units=case when coalesce(v_is_notebook,false) and coalesce(jsonb_array_length(p_storage_units),0)=0 then null else storage_units end, accessories=case when coalesce(v_is_notebook,false) and coalesce(cardinality(p_accessories),0)=0 then null else accessories end where id=v_device_id;
  return v_device_id;
end; $$;


ALTER FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_org uuid:=public.assert_reception_owner(); v_device_id uuid; v_model text:=regexp_replace(trim(p_model),'\s+',' ','g');
  v_item record; v_field record; v_text text; v_option uuid;
begin
  perform 1 from public.customers where id=p_customer_id and organization_id=v_org;
  if not found then raise exception 'INVALID_CUSTOMER'; end if;
  perform 1 from public.device_types where id=p_type_id and is_active and (organization_id is null or organization_id=v_org);
  if not found then raise exception 'INVALID_DEVICE_TYPE'; end if;
  perform 1 from public.device_brands where id=p_brand_id and is_active and (organization_id is null or organization_id=v_org);
  if not found then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if char_length(v_model) not between 2 and 120 then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_model_id is not null then
    perform 1 from public.device_models where id=p_model_id and device_type_id=p_type_id and brand_id=p_brand_id and is_active and (organization_id is null or organization_id=v_org);
    if not found then raise exception 'INVALID_DEVICE_MODEL'; end if;
  end if;
  if jsonb_typeof(coalesce(p_attributes,'{}'::jsonb)) <> 'object' then raise exception 'INVALID_DEVICE_FIELDS'; end if;
  for v_field in
    select tf.id, f.key, tf.required from public.device_type_fields tf
    join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and tf.required
  loop
    if nullif(trim(coalesce(p_attributes->>v_field.key,'')),'') is null then
      raise exception 'REQUIRED_DEVICE_FIELD';
    end if;
  end loop;
  for v_item in select key,value from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) loop
    select tf.id, f.id as field_id, f.field_type, f.data_source_key, tf.required
    into v_field from public.device_type_fields tf join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and f.key=v_item.key
    limit 1;
    if v_field.id is null then raise exception 'INVALID_DEVICE_FIELD'; end if;
    v_text:=nullif(regexp_replace(trim(coalesce(v_item.value #>> '{}','')),'\s+',' ','g'),'');
    if v_field.required and v_text is null then raise exception 'REQUIRED_DEVICE_FIELD'; end if;
  end loop;
  insert into public.customer_devices(organization_id,customer_id,type_id,brand_id,model_id,model,year,color,serial_number,imei_1,imei_2,attributes,memory_modules,storage_units,accessories,created_by)
  values(v_org,p_customer_id,p_type_id,p_brand_id,p_model_id,v_model,nullif(p_year,'')::smallint,nullif(trim(p_color),''),nullif(trim(p_serial_number),''),coalesce(nullif(trim(p_imei_1),''),nullif(p_attributes->>'imei_1','')),coalesce(nullif(trim(p_imei_2),''),nullif(p_attributes->>'imei_2','')),coalesce(p_attributes,'{}'),coalesce(p_memories,'[]'),coalesce(p_storage_units,'[]'),coalesce(p_accessories,'{}'),auth.uid()) returning id into v_device_id;
  for v_item in select key,value from jsonb_each(coalesce(p_attributes,'{}'::jsonb)) loop
    select tf.id, f.id as field_id, f.field_type, f.data_source_key into v_field
    from public.device_type_fields tf join public.device_fields f on f.id=tf.field_id
    where tf.device_type_id=p_type_id and tf.is_active and f.is_active and f.key=v_item.key limit 1;
    v_text:=nullif(regexp_replace(trim(coalesce(v_item.value #>> '{}','')),'\s+',' ','g'),'');
    if v_text is null then continue; end if;
    v_option:=null;
    if v_field.data_source_key is null and v_field.field_type in ('SELECT','RADIO') then
      select id into v_option from public.device_field_options where field_id=v_field.field_id and is_active and value=v_text and (organization_id is null or organization_id=v_org) order by organization_id nulls first limit 1;
      if v_option is null then raise exception 'INVALID_DEVICE_FIELD_OPTION'; end if;
    end if;
    insert into public.customer_device_field_values(organization_id,customer_device_id,device_type_field_id,option_id,value_text,value_boolean)
    values(v_org,v_device_id,v_field.id,v_option,case when v_option is null and v_field.field_type not in ('SWITCH','CHECKBOX') then v_text else null end,case when v_field.field_type in ('SWITCH','CHECKBOX') then (v_text='true') else null end)
    on conflict(customer_device_id,device_type_field_id) do update set option_id=excluded.option_id,value_text=excluded.value_text,value_boolean=excluded.value_boolean,updated_at=now();
  end loop;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_CREATED','DEVICE',v_device_id,jsonb_build_object('customer_id',p_customer_id,'model_id',p_model_id,'dynamic_form',true));
  return v_device_id;
end; $$;


ALTER FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_catalog_name"("p_value" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT PARALLEL SAFE
    SET "search_path" TO ''
    AS $$
  select translate(
    lower(regexp_replace(btrim(p_value), '[[:space:]]+', ' ', 'g')),
    'áéíóúüñ',
    'aeiouun'
  )
$$;


ALTER FUNCTION "public"."normalize_catalog_name"("p_value" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") IS 'Normaliza espacios, mayúsculas y diacríticos para comparar catálogos sin alterar el nombre visible.';



CREATE TABLE IF NOT EXISTS "public"."hardware_catalog_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "kind" "text" NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hardware_catalog_models_kind_check" CHECK (("kind" = ANY (ARRAY['PROCESSOR'::"text", 'MOTHERBOARD'::"text", 'GPU'::"text", 'POWER_SUPPLY'::"text", 'CASE'::"text", 'CPU_COOLER'::"text", 'WIFI_ADAPTER'::"text"]))),
    CONSTRAINT "hardware_catalog_models_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 200)))
);


ALTER TABLE "public"."hardware_catalog_models" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") RETURNS "public"."hardware_catalog_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_org uuid := public.assert_reception_owner();
  v_kind text := upper(btrim(coalesce(p_kind, '')));
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '[[:space:]]+', ' ', 'g');
  v_brand public.hardware_catalog_brands;
  v_existing public.hardware_catalog_models;
  v_created public.hardware_catalog_models;
begin
  if v_kind not in ('PROCESSOR','MOTHERBOARD','GPU','POWER_SUPPLY','CASE','CPU_COOLER','WIFI_ADAPTER') then raise exception 'INVALID_HARDWARE_KIND'; end if;
  if char_length(v_name) not between 2 and 200 then raise exception 'INVALID_HARDWARE_MODEL'; end if;
  select * into v_brand from public.hardware_catalog_brands
    where id = p_brand_id and kind = v_kind and is_active and (organization_id is null or organization_id = v_org);
  if not found then raise exception 'INVALID_HARDWARE_BRAND'; end if;
  select * into v_existing from public.hardware_catalog_models
    where kind = v_kind and brand_id = p_brand_id and normalized_name = public.normalize_catalog_name(v_name)
      and is_active and (organization_id is null or organization_id = v_org)
    order by organization_id nulls first limit 1;
  if found then return v_existing; end if;
  insert into public.hardware_catalog_models(organization_id, kind, brand_id, name, created_by)
  values (v_org, v_kind, p_brand_id, v_name, auth.uid())
  on conflict (organization_id, kind, brand_id, normalized_name) where organization_id is not null do update set name = hardware_catalog_models.name
  returning * into v_created;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values(v_org, auth.uid(), 'HARDWARE_CATALOG_MODEL_CREATED', 'HARDWARE_CATALOG_MODEL', v_created.id, jsonb_build_object('kind', v_kind, 'brand_id', p_brand_id));
  return v_created;
end; $$;


ALTER FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "first_name" "text", "last_name" "text", "phone" "text", "contact_email" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
exception when unique_violation then if v_email is not null and exists(select 1 from public.customers c where c.organization_id=v_org and lower(c.contact_email)=v_email) then raise exception 'CUSTOMER_EMAIL_EXISTS'; else raise exception 'CUSTOMER_PHONE_EXISTS'; end if; end; $_$;


ALTER FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_app_role"() RETURNS "public"."app_role"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select p.role
  from public.profiles p
  left join public.organizations o on o.id = p.organization_id
  where p.id = auth.uid()
    and p.status = 'ACTIVE'
    and (p.role = 'SUPERADMIN' or (o.id is not null and o.status = 'ACTIVE'))
$$;


ALTER FUNCTION "public"."current_app_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ select organization_id from public.profiles where id = auth.uid() $$;


ALTER FUNCTION "public"."current_organization_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_is_active"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce((select status = 'ACTIVE' from public.organizations where id = public.current_organization_id()), false)
$$;


ALTER FUNCTION "public"."current_organization_is_active"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_organization_setup_completed"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(initial_setup_completed, false)
  from public.organizations
  where id = public.current_organization_id()
$$;


ALTER FUNCTION "public"."current_organization_setup_completed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_due_account_deletions"() RETURNS TABLE("request_id" "uuid", "subject_type" "text", "organization_id" "uuid", "target_user_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_request public.account_deletion_requests%rowtype;
  v_open integer;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then raise exception 'FORBIDDEN'; end if;
  for v_request in
    select * from public.account_deletion_requests where status = 'PENDING' and scheduled_for <= now() order by scheduled_for for update skip locked
  loop
    if v_request.subject_type = 'ORGANIZATION' then
      select count(*) into v_open from public.device_receptions where organization_id = v_request.organization_id and status = 'CONFIRMED';
    else
      select count(*) into v_open from public.device_receptions r join public.customer_user_links l on l.customer_id=r.customer_id and l.organization_id=r.organization_id
      where l.auth_user_id=v_request.target_user_id and r.status='CONFIRMED';
    end if;
    if v_open > 0 then continue; end if;

    if v_request.subject_type = 'CUSTOMER_ACCOUNT' then
      update public.customers c set portal_account_deleted_at = now()
      where exists (select 1 from public.customer_user_links l where l.customer_id=c.id and l.organization_id=c.organization_id and l.auth_user_id=v_request.target_user_id);
      delete from public.customer_user_links where auth_user_id=v_request.target_user_id;
      delete from public.user_quick_links where user_id=v_request.target_user_id;
      update public.profiles set first_name=null,last_name=null,display_name='Cuenta eliminada',status='DISABLED' where id=v_request.target_user_id;
    else
      delete from public.user_quick_links where user_id in (select id from public.profiles where organization_id=v_request.organization_id);
      update public.profiles set first_name=null,last_name=null,display_name='Cuenta eliminada',status='DISABLED' where organization_id=v_request.organization_id;
    end if;

    update public.account_deletion_requests set status='COMPLETED',completed_at=now() where id=v_request.id;
    insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
    values (v_request.organization_id, null, v_request.subject_type || '_DELETION_COMPLETED', v_request.subject_type,
      coalesce(v_request.organization_id, v_request.target_user_id), jsonb_build_object('request_id',v_request.id,'status','COMPLETED'));
    request_id:=v_request.id; subject_type:=v_request.subject_type; organization_id:=v_request.organization_id; target_user_id:=v_request.target_user_id;
    return next;
  end loop;
end;
$$;


ALTER FUNCTION "public"."finalize_due_account_deletions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_initial_organization_setup"() RETURNS TABLE("status" "text", "incomplete_section" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."finalize_initial_organization_setup"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."finalize_initial_organization_setup"() IS 'Valida datos persistidos, completa el onboarding y registra auditoría en una única transacción idempotente.';



CREATE OR REPLACE FUNCTION "public"."get_my_pending_deletion"() RETURNS TABLE("id" "uuid", "subject_type" "text", "organization_id" "uuid", "reason" "text", "requested_at" timestamp with time zone, "scheduled_for" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select r.id, r.subject_type, r.organization_id, r.reason, r.requested_at, r.scheduled_for
  from public.account_deletion_requests r
  where r.status = 'PENDING'
    and (
      r.target_user_id = auth.uid()
      or r.requested_by = auth.uid()
      or (r.subject_type='ORGANIZATION' and exists (
        select 1 from public.profiles p where p.id=auth.uid() and p.role='OWNER' and p.status='ACTIVE' and p.organization_id=r.organization_id
      ))
    )
  order by r.requested_at desc
  limit 1
$$;


ALTER FUNCTION "public"."get_my_pending_deletion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.profiles p
    join public.organizations o on o.id = p.organization_id
    where p.id = auth.uid()
      and p.organization_id = p_organization_id
      and p.role = 'OWNER'
      and p.status = 'ACTIVE'
      and o.status = 'ACTIVE'
      and o.initial_setup_completed
  )
$$;


ALTER FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text" DEFAULT NULL::"text", "p_entity_id" "uuid" DEFAULT NULL::"uuid", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_id uuid;
begin
  if p_metadata::text ~* '(password|token|secret|cookie|authorization)' then raise exception 'Sensitive metadata is not allowed'; end if;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (public.current_organization_id(), auth.uid(), upper(left(p_event_type, 100)), upper(left(p_entity_type, 80)), p_entity_id, coalesce(p_metadata, '{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if current_user not in ('postgres','service_role','supabase_admin') then raise exception 'FORBIDDEN'; end if;
  update public.account_deletion_requests set auth_cleanup_completed=true where id=p_request_id and status='COMPLETED';
end; $$;


ALTER FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_confirmed_reception_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin raise exception 'CONFIRMED_RECEPTION_IMMUTABLE'; end; $$;


ALTER FUNCTION "public"."prevent_confirmed_reception_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_inventory_movement_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  raise exception 'Inventory movements are immutable';
end;
$$;


ALTER FUNCTION "public"."prevent_inventory_movement_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_inventory_stock_direct_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.current_stock is distinct from old.current_stock
    and coalesce(current_setting('nodo.inventory_stock_write', true), 'off') <> 'on'
  then
    raise exception 'Inventory stock must be changed through record_inventory_movement';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."prevent_inventory_stock_direct_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_profile_privilege_escalation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."prevent_profile_privilege_escalation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_inventory_record_identity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if new.organization_id is distinct from old.organization_id
    or new.created_by is distinct from old.created_by
  then
    raise exception 'Inventory ownership fields are immutable';
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."protect_inventory_record_identity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric DEFAULT NULL::numeric, "p_reference_type" "text" DEFAULT NULL::"text", "p_reference_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_organization_id uuid := public.assert_inventory_owner();
  v_movement_id uuid;
  v_stock_before numeric(14,3);
  v_stock_after numeric(14,3);
  v_quantity_delta numeric(14,3);
  v_reason text := regexp_replace(btrim(coalesce(p_reason, '')), '[[:space:]]+', ' ', 'g');
  v_reference_type text := nullif(
    upper(regexp_replace(btrim(coalesce(p_reference_type, '')), '[[:space:]]+', '_', 'g')),
    ''
  );
begin
  if p_movement_type is null or p_quantity is null or p_quantity = 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  if p_movement_type in ('IN', 'OUT') and p_quantity < 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  v_quantity_delta := case p_movement_type
    when 'IN' then p_quantity
    when 'OUT' then -p_quantity
    when 'ADJUSTMENT' then p_quantity
  end;

  if char_length(v_reason) not between 3 and 500 then
    raise exception 'INVALID_REASON';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'INVALID_UNIT_COST';
  end if;

  if (v_reference_type is null) <> (p_reference_id is null) then
    raise exception 'INVALID_REFERENCE';
  end if;

  if v_reference_type is not null
    and v_reference_type !~ '^[A-Z][A-Z0-9_]{1,49}$'
  then
    raise exception 'INVALID_REFERENCE_TYPE';
  end if;

  select i.current_stock
  into v_stock_before
  from public.inventory_items i
  where i.id = p_inventory_item_id
    and i.organization_id = v_organization_id
    and i.is_active
  for update;

  if not found then
    raise exception 'INVENTORY_ITEM_NOT_FOUND';
  end if;

  v_stock_after := v_stock_before + v_quantity_delta;
  if v_stock_after < 0 then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  perform set_config('nodo.inventory_stock_write', 'on', true);
  update public.inventory_items
  set current_stock = v_stock_after
  where id = p_inventory_item_id
    and organization_id = v_organization_id;
  perform set_config('nodo.inventory_stock_write', 'off', true);

  insert into public.inventory_movements (
    organization_id,
    inventory_item_id,
    movement_type,
    quantity_delta,
    stock_before,
    stock_after,
    unit_cost,
    reason,
    reference_type,
    reference_id,
    actor_user_id
  ) values (
    v_organization_id,
    p_inventory_item_id,
    p_movement_type,
    v_quantity_delta,
    v_stock_before,
    v_stock_after,
    p_unit_cost,
    v_reason,
    v_reference_type,
    p_reference_id,
    auth.uid()
  )
  returning id into v_movement_id;

  return v_movement_id;
end;
$_$;


ALTER FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") IS 'Registra IN/OUT con cantidad positiva; ADJUSTMENT admite una diferencia con signo. Rechaza saldos negativos.';



CREATE OR REPLACE FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin perform 1 from public.device_receptions where id=p_reception_id and organization_id=v_org; if not found or p_storage_path not like v_org::text||'/'||p_reception_id::text||'/%' then raise exception 'INVALID_PHOTO'; end if;
 insert into public.reception_photos(organization_id,reception_id,storage_path,description,inspection_item_key,uploaded_by) values(v_org,p_reception_id,p_storage_path,nullif(trim(p_description),''),nullif(p_inspection_key,''),auth.uid()) returning id into v_id; return v_id; end; $$;


ALTER FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile public.profiles%rowtype;
  v_reason text := regexp_replace(trim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_open_receptions integer;
  v_request_id uuid;
  v_scheduled_for timestamptz := now() + interval '30 days';
begin
  select * into v_profile from public.profiles where id = auth.uid() for update;
  if not found or v_profile.role <> 'CUSTOMER' or v_profile.status <> 'ACTIVE' then raise exception 'FORBIDDEN'; end if;
  if v_profile.organization_id is not null and not exists (
    select 1 from public.organizations where id=v_profile.organization_id and status='ACTIVE'
  ) then raise exception 'ORGANIZATION_UNAVAILABLE'; end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'INVALID_REASON'; end if;

  select count(*) into v_open_receptions
  from public.device_receptions r
  join public.customer_user_links l
    on l.customer_id = r.customer_id and l.organization_id = r.organization_id
  where l.auth_user_id = auth.uid() and r.status = 'CONFIRMED';

  if v_open_receptions > 0 then
    return jsonb_build_object(
      'ok', false,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'OPEN_RECEPTIONS',
        'count', v_open_receptions,
        'message', format('Tenés %s reparacion(es) o equipo(s) pendientes de resolución/retiro.', v_open_receptions)
      ))
    );
  end if;

  insert into public.account_deletion_requests
    (subject_type, organization_id, target_user_id, requested_by, reason, scheduled_for)
  values ('CUSTOMER_ACCOUNT', v_profile.organization_id, auth.uid(), auth.uid(), v_reason, v_scheduled_for)
  returning id into v_request_id;

  update public.profiles set status = 'SUSPENDED' where id = auth.uid();
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_profile.organization_id, auth.uid(), 'CUSTOMER_ACCOUNT_DELETION_REQUESTED', 'PROFILE', auth.uid(),
    jsonb_build_object('request_id', v_request_id, 'reason', v_reason, 'status', 'PENDING', 'scheduled_for', v_scheduled_for));

  return jsonb_build_object('ok', true, 'requestId', v_request_id, 'scheduledFor', v_scheduled_for);
end;
$$;


ALTER FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_organization_deletion"("p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_profile public.profiles%rowtype;
  v_organization public.organizations%rowtype;
  v_reason text := regexp_replace(trim(coalesce(p_reason, '')), '\s+', ' ', 'g');
  v_open_receptions integer;
  v_request_id uuid;
  v_scheduled_for timestamptz := now() + interval '30 days';
begin
  select * into v_profile from public.profiles where id = auth.uid() for update;
  if not found or v_profile.role <> 'OWNER' or v_profile.status <> 'ACTIVE' or v_profile.organization_id is null then
    raise exception 'FORBIDDEN';
  end if;
  if char_length(v_reason) not between 3 and 300 then raise exception 'INVALID_REASON'; end if;

  select * into v_organization from public.organizations where id = v_profile.organization_id for update;
  if not found or v_organization.status <> 'ACTIVE' then raise exception 'ORGANIZATION_UNAVAILABLE'; end if;

  select count(*) into v_open_receptions
  from public.device_receptions
  where organization_id = v_organization.id and status = 'CONFIRMED';

  if v_open_receptions > 0 then
    return jsonb_build_object(
      'ok', false,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'OPEN_RECEPTIONS',
        'count', v_open_receptions,
        'message', format('Hay %s reparacion(es) o equipo(s) pendientes de resolución/retiro.', v_open_receptions)
      ))
    );
  end if;

  insert into public.account_deletion_requests
    (subject_type, organization_id, requested_by, reason, scheduled_for)
  values ('ORGANIZATION', v_organization.id, auth.uid(), v_reason, v_scheduled_for)
  returning id into v_request_id;

  update public.organizations set status = 'SUSPENDED' where id = v_organization.id;
  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_organization.id, auth.uid(), 'ORGANIZATION_DELETION_REQUESTED', 'ORGANIZATION', v_organization.id,
    jsonb_build_object('request_id', v_request_id, 'reason', v_reason, 'status', 'PENDING', 'scheduled_for', v_scheduled_for));

  return jsonb_build_object('ok', true, 'requestId', v_request_id, 'scheduledFor', v_scheduled_for);
end;
$$;


ALTER FUNCTION "public"."request_organization_deletion"("p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ delete from public.auth_rate_limits where action = upper(p_action) and key_hash = p_key_hash $$;


ALTER FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") IS 'Guarda únicamente identidad y logo del OWNER autenticado y avanza el onboarding al paso 2.';



CREATE OR REPLACE FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") RETURNS smallint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;


ALTER FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") IS 'Guarda únicamente teléfono E.164 y email de contacto del OWNER autenticado y avanza el onboarding al paso 3.';



CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;


ALTER FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_organization_id uuid := public.current_organization_id();
  v_name text := regexp_replace(trim(p_name), '[[:space:]]+', ' ', 'g');
  v_logo_path text := nullif(trim(p_logo_path), '');
  v_phone text := trim(p_phone);
  v_phone_country_code text := upper(trim(p_phone_country_code));
  v_phone_calling_code text := trim(p_phone_calling_code);
  v_phone_national_number text := trim(p_phone_national_number);
  v_contact_email text := lower(trim(p_contact_email));
  v_neighborhood_id text := nullif(trim(p_neighborhood_id), '');
  v_street text := regexp_replace(trim(p_street), '[[:space:]]+', ' ', 'g');
  v_locality_name text;
  v_province_name text;
  v_old_logo_path text;
begin
  if auth.uid() is null
    or public.current_app_role() <> 'OWNER'
    or v_organization_id is null
    or not exists (
      select 1 from public.profiles
      where id = auth.uid()
        and role = 'OWNER'
        and status = 'ACTIVE'
        and organization_id = v_organization_id
    ) then raise exception 'Forbidden'; end if;

  select logo_path into v_old_logo_path
  from public.organizations
  where id = v_organization_id and status = 'ACTIVE' and initial_setup_completed
  for update;
  if not found then raise exception 'Organization not available'; end if;

  if char_length(v_name) not between 2 and 120 or v_name ~ '[<>]' or v_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid organization name';
  end if;
  if v_phone_country_code !~ '^[A-Z]{2}$'
    or v_phone_calling_code !~ '^\+[1-9][0-9]{0,3}$'
    or v_phone_national_number !~ '^[0-9]{4,15}$'
    or v_phone <> v_phone_calling_code || v_phone_national_number
    or (v_phone_country_code = 'AR' and char_length(v_phone_national_number) <> 10) then
    raise exception 'Invalid phone';
  end if;
  if v_contact_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or char_length(v_contact_email) > 254 then
    raise exception 'Invalid email';
  end if;
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
  if v_logo_path is not null and (
    char_length(v_logo_path) > 500
    or v_logo_path not like v_organization_id::text || '/%'
    or v_logo_path like '%..%'
  ) then raise exception 'Invalid logo path'; end if;

  select name into v_locality_name from public.localities where id = p_locality_id;
  select name into v_province_name from public.provinces where id = p_province_id;

  update public.organizations
  set
    name = v_name,
    trade_name = v_name,
    logo_path = v_logo_path,
    phone = v_phone,
    phone_country_code = v_phone_country_code,
    phone_calling_code = v_phone_calling_code,
    phone_national_number = v_phone_national_number,
    contact_email = v_contact_email,
    address = v_street || ' ' || case when p_without_number then 'S/N' else p_street_number::text end,
    locality = v_locality_name,
    province = v_province_name
  where id = v_organization_id;

  insert into public.organization_addresses (
    organization_id, country_id, province_id, locality_id, neighborhood_id,
    street, street_number, without_number
  ) values (
    v_organization_id, p_country_id, p_province_id, p_locality_id, v_neighborhood_id,
    v_street, p_street_number, p_without_number
  )
  on conflict (organization_id) do update set
    country_id = excluded.country_id,
    province_id = excluded.province_id,
    locality_id = excluded.locality_id,
    neighborhood_id = excluded.neighborhood_id,
    street = excluded.street,
    street_number = excluded.street_number,
    without_number = excluded.without_number;

  insert into public.audit_events (organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (
    v_organization_id,
    auth.uid(),
    'ORGANIZATION_UPDATED',
    'ORGANIZATION',
    v_organization_id,
    jsonb_build_object(
      'sections', jsonb_build_array('identity', 'contact', 'location'),
      'logo_updated', v_logo_path is distinct from v_old_logo_path
    )
  );
end;
$_$;


ALTER FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) IS 'Actualiza de forma transaccional los datos no administrativos y el domicilio de la organización OWNER autenticada.';



CREATE OR REPLACE FUNCTION "public"."validate_desktop_hardware_values"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid; v_type text; v_processor_brand uuid; v_processor_model uuid;
begin
  select d.organization_id,t.name into v_org,v_type from public.customer_devices d join public.device_types t on t.id=d.type_id where d.id=new.customer_device_id;
  if v_type is distinct from 'PC' then return null; end if;
  select nullif(value_text,'')::uuid into v_processor_brand from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_brand_id';
  select nullif(value_text,'')::uuid into v_processor_model from public.customer_device_field_values v join public.device_type_fields tf on tf.id=v.device_type_field_id join public.device_fields f on f.id=tf.field_id where v.customer_device_id=new.customer_device_id and f.key='processor_model_id';
  if v_processor_model is not null and not exists (select 1 from public.hardware_catalog_models m where m.id=v_processor_model and m.kind='PROCESSOR' and m.brand_id=v_processor_brand and m.is_active and (m.organization_id is null or m.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_MODEL'; end if;
  if v_processor_brand is not null and not exists (select 1 from public.hardware_catalog_brands b where b.id=v_processor_brand and b.kind='PROCESSOR' and b.is_active and (b.organization_id is null or b.organization_id=v_org)) then raise exception 'INVALID_PROCESSOR_BRAND'; end if;
  return null;
end; $$;


ALTER FUNCTION "public"."validate_desktop_hardware_values"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_deletion_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subject_type" "text" NOT NULL,
    "organization_id" "uuid",
    "target_user_id" "uuid",
    "requested_by" "uuid",
    "reason" "text" NOT NULL,
    "status" "text" DEFAULT 'PENDING'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "scheduled_for" timestamp with time zone DEFAULT ("now"() + '30 days'::interval) NOT NULL,
    "cancelled_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "auth_cleanup_completed" boolean DEFAULT false NOT NULL,
    CONSTRAINT "account_deletion_requests_reason_check" CHECK ((("char_length"(TRIM(BOTH FROM "reason")) >= 3) AND ("char_length"(TRIM(BOTH FROM "reason")) <= 300))),
    CONSTRAINT "account_deletion_requests_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'CANCELLED'::"text", 'COMPLETED'::"text"]))),
    CONSTRAINT "account_deletion_requests_subject_type_check" CHECK (("subject_type" = ANY (ARRAY['ORGANIZATION'::"text", 'CUSTOMER_ACCOUNT'::"text"]))),
    CONSTRAINT "account_deletion_subject_check" CHECK (((("subject_type" = 'ORGANIZATION'::"text") AND ("organization_id" IS NOT NULL)) OR (("subject_type" = 'CUSTOMER_ACCOUNT'::"text") AND ("target_user_id" IS NOT NULL))))
);


ALTER TABLE "public"."account_deletion_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_deletion_requests" IS 'Solicitudes append-like de baja reversible; el histórico legal permanece en las tablas de negocio y auditoría.';



CREATE TABLE IF NOT EXISTS "public"."audit_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "actor_user_id" "uuid",
    "event_type" "text" NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "uuid",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "result" "text" DEFAULT 'SUCCESS'::"text" NOT NULL,
    CONSTRAINT "audit_events_entity_type_check" CHECK ((("char_length"("entity_type") >= 2) AND ("char_length"("entity_type") <= 80))),
    CONSTRAINT "audit_events_event_type_check" CHECK ((("char_length"("event_type") >= 3) AND ("char_length"("event_type") <= 100))),
    CONSTRAINT "audit_events_result_check" CHECK (("result" = ANY (ARRAY['SUCCESS'::"text", 'FAILURE'::"text"])))
);


ALTER TABLE "public"."audit_events" OWNER TO "postgres";


COMMENT ON COLUMN "public"."audit_events"."result" IS 'Resultado controlado del evento; nunca contiene detalles técnicos ni secretos.';



CREATE TABLE IF NOT EXISTS "public"."auth_rate_limits" (
    "action" "text" NOT NULL,
    "key_hash" "text" NOT NULL,
    "attempts" integer DEFAULT 0 NOT NULL,
    "window_started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "blocked_until" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "auth_rate_limits_attempts_check" CHECK (("attempts" >= 0)),
    CONSTRAINT "auth_rate_limits_key_hash_check" CHECK (("char_length"("key_hash") = 64))
);


ALTER TABLE "public"."auth_rate_limits" OWNER TO "postgres";


COMMENT ON TABLE "public"."auth_rate_limits" IS 'Contadores ef??meros por HMAC; nunca almacena IP ni correo en claro.';



CREATE TABLE IF NOT EXISTS "public"."component_attribute_definitions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "component_type_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "component_attribute_definitions_field_type_check" CHECK (("field_type" = ANY (ARRAY['TEXT'::"text", 'NUMBER'::"text", 'SELECT'::"text"]))),
    CONSTRAINT "component_attribute_definitions_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text"))
);


ALTER TABLE "public"."component_attribute_definitions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_attribute_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attribute_definition_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."component_attribute_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "max_instances" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."component_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."countries" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "countries_id_check" CHECK (("id" ~ '^[A-Z]{2}$'::"text")),
    CONSTRAINT "countries_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 100)))
);


ALTER TABLE "public"."countries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_field_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_device_id" "uuid" NOT NULL,
    "device_type_field_id" "uuid" NOT NULL,
    "option_id" "uuid",
    "value_text" "text",
    "value_number" numeric,
    "value_boolean" boolean,
    "value_json" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_device_field_values_check" CHECK (("num_nonnulls"("value_text", "value_number", "value_boolean", "value_json", "option_id") = 1))
);


ALTER TABLE "public"."customer_device_field_values" OWNER TO "postgres";


COMMENT ON TABLE "public"."customer_device_field_values" IS 'Valores configurables de un dispositivo. Los catálogos maestros se conservan en tablas normalizadas.';



CREATE TABLE IF NOT EXISTS "public"."customer_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "type_id" "uuid" NOT NULL,
    "brand_id" "uuid" NOT NULL,
    "model" "text",
    "year" smallint,
    "color" "text",
    "serial_number" "text",
    "imei_1" "text",
    "imei_2" "text",
    "attributes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "memory_modules" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "storage_units" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "accessories" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "model_id" "uuid",
    "family_id" "uuid",
    "variant_id" "uuid",
    "color_id" "uuid",
    "operating_system_id" "uuid",
    "mobile_operator_id" "uuid",
    "is_locked" boolean DEFAULT false NOT NULL,
    "lock_type_id" "uuid",
    CONSTRAINT "customer_devices_color_check" CHECK ((("color" IS NULL) OR ("char_length"("color") <= 80))),
    CONSTRAINT "customer_devices_imei_1_check" CHECK ((("imei_1" IS NULL) OR ("imei_1" ~ '^[0-9]{0,20}$'::"text"))),
    CONSTRAINT "customer_devices_imei_2_check" CHECK ((("imei_2" IS NULL) OR ("imei_2" ~ '^[0-9]{0,20}$'::"text"))),
    CONSTRAINT "customer_devices_model_check" CHECK ((("char_length"(TRIM(BOTH FROM "model")) >= 2) AND ("char_length"(TRIM(BOTH FROM "model")) <= 120))),
    CONSTRAINT "customer_devices_serial_number_check" CHECK ((("serial_number" IS NULL) OR ("char_length"("serial_number") <= 120))),
    CONSTRAINT "customer_devices_year_check" CHECK ((("year" >= 1950) AND ("year" <= 2200)))
);


ALTER TABLE "public"."customer_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_user_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "auth_user_id" "uuid" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."customer_user_links" OWNER TO "postgres";


COMMENT ON TABLE "public"."customer_user_links" IS 'V??nculo expl??cito y opcional entre un cliente del negocio y una identidad de Auth.';



CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "contact_email" "text",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "portal_account_deleted_at" timestamp with time zone,
    CONSTRAINT "customers_first_name_check" CHECK ((("char_length"("first_name") >= 1) AND ("char_length"("first_name") <= 80))),
    CONSTRAINT "customers_last_name_check" CHECK ((("char_length"("last_name") >= 1) AND ("char_length"("last_name") <= 80)))
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


COMMENT ON TABLE "public"."customers" IS 'Datos de contacto del cliente; no equivale a una identidad de Auth.';



CREATE TABLE IF NOT EXISTS "public"."device_accessories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_accessories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_field_dependencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_field_id" "uuid" NOT NULL,
    "parent_device_type_field_id" "uuid" NOT NULL,
    "operator" "text" DEFAULT 'EQUALS'::"text" NOT NULL,
    "expected_value" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_field_dependencies_check" CHECK (("device_type_field_id" <> "parent_device_type_field_id")),
    CONSTRAINT "device_field_dependencies_operator_check" CHECK (("operator" = ANY (ARRAY['EQUALS'::"text", 'NOT_EQUALS'::"text", 'IN'::"text", 'NOT_EMPTY'::"text", 'EMPTY'::"text"])))
);


ALTER TABLE "public"."device_field_dependencies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_field_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "field_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_field_options_label_check" CHECK ((("char_length"(TRIM(BOTH FROM "label")) >= 1) AND ("char_length"(TRIM(BOTH FROM "label")) <= 160))),
    CONSTRAINT "device_field_options_value_check" CHECK ((("char_length"(TRIM(BOTH FROM "value")) >= 1) AND ("char_length"(TRIM(BOTH FROM "value")) <= 160)))
);


ALTER TABLE "public"."device_field_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_fields" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "data_source_key" "text",
    "placeholder" "text",
    "help_text" "text",
    "validation" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_fields_data_source_key_check" CHECK ((("data_source_key" IS NULL) OR ("data_source_key" = ANY (ARRAY['brand'::"text", 'family'::"text", 'model'::"text", 'variant'::"text", 'color'::"text", 'memory_capacity'::"text", 'storage_capacity'::"text", 'operating_system'::"text", 'mobile_operator'::"text", 'accessory'::"text", 'lock_type'::"text", 'hardware_processor_brand'::"text", 'hardware_processor_model'::"text", 'hardware_motherboard_brand'::"text", 'hardware_motherboard_model'::"text", 'hardware_gpu_brand'::"text", 'hardware_gpu_model'::"text", 'hardware_power_supply_brand'::"text", 'hardware_power_supply_model'::"text", 'hardware_case_brand'::"text", 'hardware_case_model'::"text", 'hardware_cpu_cooler_brand'::"text", 'hardware_cpu_cooler_model'::"text", 'hardware_wifi_brand'::"text", 'hardware_wifi_model'::"text", 'notebook_keyboard_mount'::"text"])))),
    CONSTRAINT "device_fields_field_type_check" CHECK (("field_type" = ANY (ARRAY['TEXT'::"text", 'NUMBER'::"text", 'TEXTAREA'::"text", 'SELECT'::"text", 'MULTISELECT'::"text", 'CHECKBOX'::"text", 'RADIO'::"text", 'SWITCH'::"text", 'REPEATABLE'::"text"]))),
    CONSTRAINT "device_fields_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_fields_label_check" CHECK ((("char_length"(TRIM(BOTH FROM "label")) >= 2) AND ("char_length"(TRIM(BOTH FROM "label")) <= 120))),
    CONSTRAINT "device_fields_validation_check" CHECK (("jsonb_typeof"("validation") = 'object'::"text"))
);


ALTER TABLE "public"."device_fields" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_fields" IS 'Definición reutilizable de controles dinámicos. Los data_source_key se resuelven con código seguro en servidor; nunca contienen SQL.';



CREATE TABLE IF NOT EXISTS "public"."device_form_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "device_type_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_form_sections_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_form_sections_title_check" CHECK ((("char_length"(TRIM(BOTH FROM "title")) >= 2) AND ("char_length"(TRIM(BOTH FROM "title")) <= 100)))
);


ALTER TABLE "public"."device_form_sections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_lock_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_lock_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_model_variants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "model_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "technical_code" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_model_variants_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 140)))
);


ALTER TABLE "public"."device_model_variants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_product_families" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "brand_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "code" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_product_families_name_check" CHECK ((("char_length"(TRIM(BOTH FROM "name")) >= 2) AND ("char_length"(TRIM(BOTH FROM "name")) <= 120)))
);


ALTER TABLE "public"."device_product_families" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_reception_controls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "applicable_when_attribute" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_reception_controls_key_check" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_reception_controls_label_check" CHECK ((("char_length"("btrim"("label")) >= 2) AND ("char_length"("btrim"("label")) <= 120)))
);


ALTER TABLE "public"."device_reception_controls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_receptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "device_id" "uuid" NOT NULL,
    "reported_problem" "text" NOT NULL,
    "observations" "text" DEFAULT ''::"text" NOT NULL,
    "condition_score" numeric(6,1) NOT NULL,
    "calculated_condition" "text" NOT NULL,
    "intake_snapshot" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'CONFIRMED'::"text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_receptions_calculated_condition_check" CHECK (("calculated_condition" = ANY (ARRAY['Excelente estado'::"text", 'Buen estado'::"text", 'Desgaste normal'::"text", 'Estado regular'::"text", 'Dañado'::"text", 'Muy dañado'::"text"]))),
    CONSTRAINT "device_receptions_condition_score_check" CHECK (("condition_score" >= (0)::numeric)),
    CONSTRAINT "device_receptions_observations_check" CHECK (("char_length"("observations") <= 2000)),
    CONSTRAINT "device_receptions_reported_problem_check" CHECK ((("char_length"(TRIM(BOTH FROM "reported_problem")) >= 10) AND ("char_length"(TRIM(BOTH FROM "reported_problem")) <= 2000))),
    CONSTRAINT "device_receptions_status_check" CHECK (("status" = 'CONFIRMED'::"text"))
);


ALTER TABLE "public"."device_receptions" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_receptions" IS 'Snapshot inmutable del estado observado al recibir el equipo; hallazgos posteriores deben registrarse por separado.';



CREATE TABLE IF NOT EXISTS "public"."device_type_diagnostic_tests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "diagnostic_test_type_id" "uuid" NOT NULL,
    "section_id" "uuid",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."device_type_diagnostic_tests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_fields" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "section_id" "uuid" NOT NULL,
    "field_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "overrides" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_type_fields_overrides_check" CHECK (("jsonb_typeof"("overrides") = 'object'::"text"))
);


ALTER TABLE "public"."device_type_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_services" (
    "device_type_id" "uuid" NOT NULL,
    "technical_service_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."device_type_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."diagnostic_result_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."diagnostic_result_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."diagnostic_test_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "category" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."diagnostic_test_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hardware_catalog_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "kind" "text" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "hardware_catalog_brands_kind_check" CHECK (("kind" = ANY (ARRAY['PROCESSOR'::"text", 'MOTHERBOARD'::"text", 'GPU'::"text", 'POWER_SUPPLY'::"text", 'CASE'::"text", 'CPU_COOLER'::"text", 'WIFI_ADAPTER'::"text"]))),
    CONSTRAINT "hardware_catalog_brands_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120)))
);


ALTER TABLE "public"."hardware_catalog_brands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_brands_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120)))
);


ALTER TABLE "public"."inventory_brands" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_brands" IS 'Marcas de artículos por organización; se mantiene separado de device_brands para no mezclar repuestos con dispositivos.';



CREATE TABLE IF NOT EXISTS "public"."inventory_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_categories_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 100)))
);


ALTER TABLE "public"."inventory_categories" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_categories" IS 'Catálogo global de categorías genéricas de inventario, de solo lectura para usuarios autenticados.';



CREATE TABLE IF NOT EXISTS "public"."inventory_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "category_id" "uuid" NOT NULL,
    "brand_id" "uuid",
    "preferred_supplier_id" "uuid",
    "sku" "text",
    "normalized_sku" "text" GENERATED ALWAYS AS ("upper"("btrim"("sku"))) STORED,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "description" "text",
    "cost" numeric(14,2) DEFAULT 0 NOT NULL,
    "sale_price" numeric(14,2) DEFAULT 0 NOT NULL,
    "current_stock" numeric(14,3) DEFAULT 0 NOT NULL,
    "minimum_stock" numeric(14,3) DEFAULT 0 NOT NULL,
    "unit" "text" DEFAULT 'UNIT'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_items_cost_check" CHECK (("cost" >= (0)::numeric)),
    CONSTRAINT "inventory_items_current_stock_check" CHECK (("current_stock" >= (0)::numeric)),
    CONSTRAINT "inventory_items_description_check" CHECK ((("description" IS NULL) OR ("char_length"("description") <= 2000))),
    CONSTRAINT "inventory_items_minimum_stock_check" CHECK (("minimum_stock" >= (0)::numeric)),
    CONSTRAINT "inventory_items_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 160))),
    CONSTRAINT "inventory_items_sale_price_check" CHECK (("sale_price" >= (0)::numeric)),
    CONSTRAINT "inventory_items_sku_check" CHECK ((("sku" IS NULL) OR (("char_length"("btrim"("sku")) >= 1) AND ("char_length"("btrim"("sku")) <= 80)))),
    CONSTRAINT "inventory_items_unit_check" CHECK (("unit" ~ '^[A-Z][A-Z0-9_]{0,19}$'::"text"))
);


ALTER TABLE "public"."inventory_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "inventory_item_id" "uuid" NOT NULL,
    "movement_type" "public"."inventory_movement_type" NOT NULL,
    "quantity_delta" numeric(14,3) NOT NULL,
    "stock_before" numeric(14,3) NOT NULL,
    "stock_after" numeric(14,3) NOT NULL,
    "unit_cost" numeric(14,2),
    "reason" "text" NOT NULL,
    "reference_type" "text",
    "reference_id" "uuid",
    "actor_user_id" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inventory_movements_balance_check" CHECK (("stock_after" = ("stock_before" + "quantity_delta"))),
    CONSTRAINT "inventory_movements_delta_type_check" CHECK (((("movement_type" = 'IN'::"public"."inventory_movement_type") AND ("quantity_delta" > (0)::numeric)) OR (("movement_type" = 'OUT'::"public"."inventory_movement_type") AND ("quantity_delta" < (0)::numeric)) OR (("movement_type" = 'ADJUSTMENT'::"public"."inventory_movement_type") AND ("quantity_delta" <> (0)::numeric)))),
    CONSTRAINT "inventory_movements_reason_check" CHECK ((("char_length"("btrim"("reason")) >= 3) AND ("char_length"("btrim"("reason")) <= 500))),
    CONSTRAINT "inventory_movements_reference_pair_check" CHECK (((("reference_type" IS NULL) AND ("reference_id" IS NULL)) OR (("reference_type" IS NOT NULL) AND ("reference_id" IS NOT NULL)))),
    CONSTRAINT "inventory_movements_reference_type_check" CHECK ((("reference_type" IS NULL) OR ("reference_type" ~ '^[A-Z][A-Z0-9_]{1,49}$'::"text"))),
    CONSTRAINT "inventory_movements_stock_after_check" CHECK (("stock_after" >= (0)::numeric)),
    CONSTRAINT "inventory_movements_stock_before_check" CHECK (("stock_before" >= (0)::numeric)),
    CONSTRAINT "inventory_movements_unit_cost_check" CHECK ((("unit_cost" IS NULL) OR ("unit_cost" >= (0)::numeric)))
);


ALTER TABLE "public"."inventory_movements" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_movements" IS 'Historial inmutable y atómico que mantiene sincronizado inventory_items.current_stock.';



CREATE TABLE IF NOT EXISTS "public"."localities" (
    "id" "text" NOT NULL,
    "province_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "localities_id_check" CHECK ((("char_length"("id") >= 1) AND ("char_length"("id") <= 40))),
    CONSTRAINT "localities_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 140)))
);


ALTER TABLE "public"."localities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."memory_capacities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "capacity_mb" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."memory_capacities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mobile_operators" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "country_code" "text" DEFAULT 'AR'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."mobile_operators" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."neighborhoods" (
    "id" "text" NOT NULL,
    "locality_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "neighborhoods_id_check" CHECK ((("char_length"("id") >= 1) AND ("char_length"("id") <= 80))),
    CONSTRAINT "neighborhoods_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 140)))
);


ALTER TABLE "public"."neighborhoods" OWNER TO "postgres";


COMMENT ON TABLE "public"."neighborhoods" IS 'Catálogo global de barrios. El conjunto inicial de Formosa capital proviene de bdformostock_schema.sql.';



CREATE TABLE IF NOT EXISTS "public"."notebook_keyboard_mount_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text" NOT NULL,
    "image_reference" "text",
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notebook_keyboard_mount_types_description_check" CHECK ((("char_length"("btrim"("description")) >= 10) AND ("char_length"("btrim"("description")) <= 1000))),
    CONSTRAINT "notebook_keyboard_mount_types_image_reference_check" CHECK ((("image_reference" IS NULL) OR ("char_length"("btrim"("image_reference")) <= 500))),
    CONSTRAINT "notebook_keyboard_mount_types_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 100)))
);


ALTER TABLE "public"."notebook_keyboard_mount_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."operating_systems" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "platform" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."operating_systems" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organization_addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "country_id" "text" NOT NULL,
    "province_id" "text" NOT NULL,
    "locality_id" "text" NOT NULL,
    "neighborhood_id" "text",
    "street" "text" NOT NULL,
    "street_number" integer,
    "without_number" boolean DEFAULT false NOT NULL,
    "floor" "text",
    "apartment" "text",
    "postal_code" "text",
    "reference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "organization_addresses_apartment_check" CHECK ((("apartment" IS NULL) OR (("char_length"("apartment") <= 10) AND ("apartment" !~ '[<>]'::"text") AND ("apartment" !~ '[[:cntrl:]]'::"text")))),
    CONSTRAINT "organization_addresses_floor_check" CHECK ((("floor" IS NULL) OR (("char_length"("floor") <= 10) AND ("floor" !~ '[<>]'::"text") AND ("floor" !~ '[[:cntrl:]]'::"text")))),
    CONSTRAINT "organization_addresses_number_check" CHECK ((("without_number" AND ("street_number" IS NULL)) OR ((NOT "without_number") AND ("street_number" IS NOT NULL)))),
    CONSTRAINT "organization_addresses_postal_code_check" CHECK ((("postal_code" IS NULL) OR (("char_length"("postal_code") >= 4) AND ("char_length"("postal_code") <= 10)))),
    CONSTRAINT "organization_addresses_reference_check" CHECK ((("reference" IS NULL) OR (("char_length"("reference") <= 200) AND ("reference" !~ '[<>]'::"text") AND ("reference" !~ '[[:cntrl:]]'::"text")))),
    CONSTRAINT "organization_addresses_street_check" CHECK (((("char_length"("street") >= 2) AND ("char_length"("street") <= 120)) AND ("street" !~ '[<>]'::"text") AND ("street" !~ '[[:cntrl:]]'::"text"))),
    CONSTRAINT "organization_addresses_street_number_check" CHECK ((("street_number" >= 1) AND ("street_number" <= 999999)))
);


ALTER TABLE "public"."organization_addresses" OWNER TO "postgres";


COMMENT ON TABLE "public"."organization_addresses" IS 'Domicilio principal estructurado. Lectura protegida por RLS; escritura exclusivamente mediante RPC autorizada y auditada.';



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "status" "public"."organization_status" DEFAULT 'ACTIVE'::"public"."organization_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "trade_name" "text",
    "logo_path" "text",
    "phone" "text",
    "contact_email" "text",
    "address" "text",
    "locality" "text",
    "province" "text",
    "description" "text",
    "initial_setup_completed" boolean DEFAULT false NOT NULL,
    "initial_setup_step" smallint DEFAULT 1 NOT NULL,
    "phone_country_code" "text",
    "phone_calling_code" "text",
    "phone_national_number" "text",
    CONSTRAINT "organizations_initial_setup_step_check" CHECK ((("initial_setup_step" >= 1) AND ("initial_setup_step" <= 4))),
    CONSTRAINT "organizations_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 120))),
    CONSTRAINT "organizations_name_format_check" CHECK (((("char_length"("name") >= 2) AND ("char_length"("name") <= 120)) AND ("name" !~ '[<>]'::"text") AND ("name" !~ '[[:cntrl:]]'::"text"))),
    CONSTRAINT "organizations_phone_components_check" CHECK (((("phone_country_code" IS NULL) AND ("phone_calling_code" IS NULL) AND ("phone_national_number" IS NULL)) OR (("phone_country_code" ~ '^[A-Z]{2}$'::"text") AND ("phone_calling_code" ~ '^\+[1-9][0-9]{0,3}$'::"text") AND ("phone_national_number" ~ '^[0-9]{4,15}$'::"text") AND ("phone" = ("phone_calling_code" || "phone_national_number"))))),
    CONSTRAINT "organizations_setup_fields_length" CHECK (((("trade_name" IS NULL) OR (("char_length"("trade_name") >= 2) AND ("char_length"("trade_name") <= 120))) AND (("logo_path" IS NULL) OR ("char_length"("logo_path") <= 500)) AND (("phone" IS NULL) OR (("char_length"("phone") >= 6) AND ("char_length"("phone") <= 30))) AND (("contact_email" IS NULL) OR ("char_length"("contact_email") <= 254)) AND (("address" IS NULL) OR (("char_length"("address") >= 3) AND ("char_length"("address") <= 180))) AND (("locality" IS NULL) OR (("char_length"("locality") >= 2) AND ("char_length"("locality") <= 100))) AND (("province" IS NULL) OR (("char_length"("province") >= 2) AND ("char_length"("province") <= 100))) AND (("description" IS NULL) OR (("char_length"("description") >= 10) AND ("char_length"("description") <= 600))))),
    CONSTRAINT "organizations_slug_check" CHECK (((("char_length"("slug") >= 2) AND ("char_length"("slug") <= 80)) AND ("slug" ~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$'::"text")))
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."organizations"."logo_path" IS 'Ruta privada dentro del bucket organization-logos; nunca almacena el archivo ni una URL firmada.';



COMMENT ON COLUMN "public"."organizations"."phone" IS 'Teléfono E.164 normalizado de contacto del negocio.';



COMMENT ON COLUMN "public"."organizations"."initial_setup_completed" IS 'Bloquea la operación hasta que el OWNER completa los datos fundamentales.';



COMMENT ON COLUMN "public"."organizations"."initial_setup_step" IS 'Próximo paso pendiente del onboarding; no reemplaza initial_setup_completed.';



COMMENT ON COLUMN "public"."organizations"."phone_country_code" IS 'Código ISO 3166-1 alpha-2 derivado y validado en servidor.';



COMMENT ON COLUMN "public"."organizations"."phone_calling_code" IS 'Prefijo telefónico internacional con signo +.';



COMMENT ON COLUMN "public"."organizations"."phone_national_number" IS 'Número nacional normalizado, sin prefijo internacional.';



CREATE TABLE IF NOT EXISTS "public"."password_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "fingerprint" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "password_history_fingerprint_check" CHECK (("fingerprint" ~ '^[a-f0-9]{64}$'::"text"))
);


ALTER TABLE "public"."password_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."password_history" IS 'Fingerprints HMAC con pepper server-side; nunca contraseñas ni hashes de auth.users.';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "organization_id" "uuid",
    "first_name" "text",
    "last_name" "text",
    "display_name" "text",
    "role" "public"."app_role" DEFAULT 'CUSTOMER'::"public"."app_role" NOT NULL,
    "status" "public"."profile_status" DEFAULT 'ACTIVE'::"public"."profile_status" NOT NULL,
    "must_change_password" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "profiles_names_length" CHECK (((("first_name" IS NULL) OR ("char_length"("first_name") <= 80)) AND (("last_name" IS NULL) OR ("char_length"("last_name") <= 80)) AND (("display_name" IS NULL) OR ("char_length"("display_name") <= 170))))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."provinces" (
    "id" "text" NOT NULL,
    "country_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    CONSTRAINT "provinces_id_check" CHECK ((("char_length"("id") >= 1) AND ("char_length"("id") <= 20))),
    CONSTRAINT "provinces_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 120)))
);


ALTER TABLE "public"."provinces" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_evidence_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."reception_evidence_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_inspection_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "reception_id" "uuid" NOT NULL,
    "item_key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "condition" "text" NOT NULL,
    "severity" numeric(3,1),
    "observation" "text" DEFAULT ''::"text" NOT NULL,
    "is_critical" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reception_inspection_items_condition_check" CHECK (("condition" = ANY (ARRAY['NO_DAMAGE'::"text", 'LIGHT_WEAR'::"text", 'SCRATCHED'::"text", 'DENTED'::"text", 'BROKEN'::"text", 'MISSING'::"text", 'NOT_WORKING'::"text", 'NOT_VERIFIABLE'::"text", 'NOT_APPLICABLE'::"text"]))),
    CONSTRAINT "reception_inspection_items_item_key_check" CHECK (("item_key" ~ '^[a-z0-9_]+$'::"text")),
    CONSTRAINT "reception_inspection_items_label_check" CHECK ((("char_length"("label") >= 2) AND ("char_length"("label") <= 100))),
    CONSTRAINT "reception_inspection_items_observation_check" CHECK (("char_length"("observation") <= 500))
);


ALTER TABLE "public"."reception_inspection_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "reception_id" "uuid" NOT NULL,
    "storage_path" "text" NOT NULL,
    "description" "text",
    "inspection_item_key" "text",
    "uploaded_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reception_photos_description_check" CHECK ((("description" IS NULL) OR ("char_length"("description") <= 300))),
    CONSTRAINT "reception_photos_inspection_item_key_check" CHECK ((("inspection_item_key" IS NULL) OR ("inspection_item_key" ~ '^[a-z0-9_]+$'::"text"))),
    CONSTRAINT "reception_photos_storage_path_check" CHECK ((("char_length"("storage_path") >= 10) AND ("char_length"("storage_path") <= 400)))
);


ALTER TABLE "public"."reception_photos" OWNER TO "postgres";


COMMENT ON TABLE "public"."reception_photos" IS 'Metadatos de evidencia privada; el archivo reside en Supabase Storage.';



CREATE TABLE IF NOT EXISTS "public"."repair_device_component_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "component_id" "uuid" NOT NULL,
    "attribute_definition_id" "uuid" NOT NULL,
    "option_id" "uuid",
    "value_text" "text"
);


ALTER TABLE "public"."repair_device_component_values" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."repair_device_components" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "customer_device_id" "uuid" NOT NULL,
    "component_type_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."repair_device_components" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."repair_device_diagnostics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "reception_id" "uuid" NOT NULL,
    "diagnostic_test_type_id" "uuid" NOT NULL,
    "result_type_id" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."repair_device_diagnostics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."service_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."service_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."storage_capacities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "capacity_gb" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."storage_capacities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalize_catalog_name"("name")) STORED,
    "legal_name" "text",
    "phone" "text",
    "email" "text",
    "website" "text",
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "suppliers_email_check" CHECK ((("email" IS NULL) OR (("char_length"("btrim"("email")) >= 3) AND ("char_length"("btrim"("email")) <= 254)))),
    CONSTRAINT "suppliers_legal_name_check" CHECK ((("legal_name" IS NULL) OR (("char_length"("btrim"("legal_name")) >= 2) AND ("char_length"("btrim"("legal_name")) <= 160)))),
    CONSTRAINT "suppliers_name_check" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120))),
    CONSTRAINT "suppliers_notes_check" CHECK ((("notes" IS NULL) OR ("char_length"("notes") <= 2000))),
    CONSTRAINT "suppliers_phone_check" CHECK ((("phone" IS NULL) OR (("char_length"("btrim"("phone")) >= 6) AND ("char_length"("btrim"("phone")) <= 30)))),
    CONSTRAINT "suppliers_website_check" CHECK ((("website" IS NULL) OR (("char_length"("btrim"("website")) >= 8) AND ("char_length"("btrim"("website")) <= 500))))
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."technical_services" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "service_category_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."technical_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_quick_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "service" "text" NOT NULL,
    "url" "text" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_quick_links_service_check" CHECK (("service" = ANY (ARRAY['GOOGLE'::"text", 'GMAIL'::"text", 'YOUTUBE'::"text", 'WHATSAPP'::"text", 'FACEBOOK'::"text", 'INSTAGRAM'::"text", 'TELEGRAM'::"text"]))),
    CONSTRAINT "user_quick_links_url_allowed" CHECK ("public"."quick_link_url_allowed"("service", "url")),
    CONSTRAINT "user_quick_links_url_check" CHECK ((("char_length"("url") >= 12) AND ("char_length"("url") <= 2048)))
);


ALTER TABLE "public"."user_quick_links" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_quick_links" IS 'Enlaces personales configurables; cada identidad accede exclusivamente a sus propios registros.';



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_rate_limits"
    ADD CONSTRAINT "auth_rate_limits_pkey" PRIMARY KEY ("action", "key_hash");



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_component_type_id_key_key" UNIQUE ("component_type_id", "key");



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_attribute_definition_id_value_key" UNIQUE ("attribute_definition_id", "value");



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."countries"
    ADD CONSTRAINT "countries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_customer_device_id_device_type_key" UNIQUE ("customer_device_id", "device_type_field_id");



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_customer_id_auth_user_id_key" UNIQUE ("customer_id", "auth_user_id");



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "device_accessories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "device_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "device_colors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "device_field_dependencies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "device_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_lock_types"
    ADD CONSTRAINT "device_lock_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "device_reception_controls_device_type_id_key_key" UNIQUE ("device_type_id", "key");



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "device_reception_controls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_device_type_id_diagnostic_test_key" UNIQUE ("device_type_id", "diagnostic_test_type_id");



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_device_type_id_section_id_field_id_key" UNIQUE ("device_type_id", "section_id", "field_id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_pkey" PRIMARY KEY ("device_type_id", "technical_service_id");



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "device_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."diagnostic_result_types"
    ADD CONSTRAINT "diagnostic_result_types_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."diagnostic_result_types"
    ADD CONSTRAINT "diagnostic_result_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hardware_catalog_brands"
    ADD CONSTRAINT "hardware_catalog_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_id_kind_brand_id_key" UNIQUE ("id", "kind", "brand_id");



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_organization_id_normalized_name_key" UNIQUE ("organization_id", "normalized_name");



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "inventory_categories_normalized_name_key" UNIQUE ("normalized_name");



ALTER TABLE ONLY "public"."inventory_categories"
    ADD CONSTRAINT "inventory_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."localities"
    ADD CONSTRAINT "localities_id_province_id_key" UNIQUE ("id", "province_id");



ALTER TABLE ONLY "public"."localities"
    ADD CONSTRAINT "localities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."memory_capacities"
    ADD CONSTRAINT "memory_capacities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mobile_operators"
    ADD CONSTRAINT "mobile_operators_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_id_locality_id_key" UNIQUE ("id", "locality_id");



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notebook_keyboard_mount_types"
    ADD CONSTRAINT "notebook_keyboard_mount_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."operating_systems"
    ADD CONSTRAINT "operating_systems_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_organization_id_key" UNIQUE ("organization_id");



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."password_history"
    ADD CONSTRAINT "password_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_id_country_id_key" UNIQUE ("id", "country_id");



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_reception_id_item_key_key" UNIQUE ("reception_id", "item_key");



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_storage_path_key" UNIQUE ("storage_path");



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_value_component_id_attribute_defini_key" UNIQUE ("component_id", "attribute_definition_id");



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_reception_id_diagnostic_test_type_key" UNIQUE ("reception_id", "diagnostic_test_type_id");



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_user_id_service_key" UNIQUE ("user_id", "service");



CREATE INDEX "account_deletion_due_idx" ON "public"."account_deletion_requests" USING "btree" ("scheduled_for") WHERE ("status" = 'PENDING'::"text");



CREATE UNIQUE INDEX "account_deletion_pending_organization_unique" ON "public"."account_deletion_requests" USING "btree" ("organization_id") WHERE (("subject_type" = 'ORGANIZATION'::"text") AND ("status" = 'PENDING'::"text"));



CREATE UNIQUE INDEX "account_deletion_pending_user_unique" ON "public"."account_deletion_requests" USING "btree" ("target_user_id") WHERE (("subject_type" = 'CUSTOMER_ACCOUNT'::"text") AND ("status" = 'PENDING'::"text"));



CREATE INDEX "audit_events_actor_created_idx" ON "public"."audit_events" USING "btree" ("actor_user_id", "created_at" DESC);



CREATE INDEX "audit_events_created_idx" ON "public"."audit_events" USING "btree" ("created_at" DESC);



CREATE INDEX "audit_events_organization_created_idx" ON "public"."audit_events" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "audit_events_result_created_idx" ON "public"."audit_events" USING "btree" ("result", "created_at" DESC);



CREATE INDEX "audit_events_type_created_idx" ON "public"."audit_events" USING "btree" ("event_type", "created_at" DESC);



CREATE INDEX "auth_rate_limits_updated_idx" ON "public"."auth_rate_limits" USING "btree" ("updated_at");



CREATE UNIQUE INDEX "component_types_global_unique" ON "public"."component_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "component_types_org_unique" ON "public"."component_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "countries_normalized_name_key" ON "public"."countries" USING "btree" ("normalized_name");



CREATE INDEX "customer_device_field_values_device_idx" ON "public"."customer_device_field_values" USING "btree" ("organization_id", "customer_device_id");



CREATE INDEX "customer_devices_customer_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "customer_id");



CREATE INDEX "customer_devices_family_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "family_id");



CREATE INDEX "customer_devices_model_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "model_id");



CREATE INDEX "customer_devices_organization_created_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "customer_devices_organization_type_idx" ON "public"."customer_devices" USING "btree" ("organization_id", "type_id");



COMMENT ON INDEX "public"."customer_devices_organization_type_idx" IS 'Acelera consultas de tipos de equipo por organización.';



CREATE INDEX "customer_user_links_organization_idx" ON "public"."customer_user_links" USING "btree" ("organization_id");



CREATE INDEX "customer_user_links_user_idx" ON "public"."customer_user_links" USING "btree" ("auth_user_id");



CREATE UNIQUE INDEX "customers_organization_email_unique" ON "public"."customers" USING "btree" ("organization_id", "lower"("contact_email")) WHERE (("contact_email" IS NOT NULL) AND ("contact_email" <> ''::"text"));



CREATE INDEX "customers_organization_idx" ON "public"."customers" USING "btree" ("organization_id");



CREATE UNIQUE INDEX "customers_organization_phone_unique" ON "public"."customers" USING "btree" ("organization_id", "phone") WHERE (("phone" IS NOT NULL) AND ("phone" <> ''::"text"));



CREATE UNIQUE INDEX "device_accessories_global_unique" ON "public"."device_accessories" USING "btree" ("lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_accessories_org_unique" ON "public"."device_accessories" USING "btree" ("organization_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_brands_global_name_unique" ON "public"."device_brands" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_brands_organization_name_unique" ON "public"."device_brands" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_colors_organization_name_unique" ON "public"."device_colors" USING "btree" ("organization_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_colors_system_name_unique" ON "public"."device_colors" USING "btree" ("lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE INDEX "device_field_dependencies_child_idx" ON "public"."device_field_dependencies" USING "btree" ("device_type_field_id");



CREATE INDEX "device_field_dependencies_parent_idx" ON "public"."device_field_dependencies" USING "btree" ("parent_device_type_field_id");



CREATE INDEX "device_field_options_field_idx" ON "public"."device_field_options" USING "btree" ("field_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "device_field_options_global_unique" ON "public"."device_field_options" USING "btree" ("field_id", "lower"("regexp_replace"(TRIM(BOTH FROM "value"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_field_options_org_unique" ON "public"."device_field_options" USING "btree" ("organization_id", "field_id", "lower"("regexp_replace"(TRIM(BOTH FROM "value"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_fields_global_key_unique" ON "public"."device_fields" USING "btree" ("key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_fields_org_key_unique" ON "public"."device_fields" USING "btree" ("organization_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_form_sections_global_unique" ON "public"."device_form_sections" USING "btree" ("device_type_id", "key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_form_sections_org_unique" ON "public"."device_form_sections" USING "btree" ("organization_id", "device_type_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "device_form_sections_type_idx" ON "public"."device_form_sections" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "device_lock_types_global_unique" ON "public"."device_lock_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_lock_types_org_unique" ON "public"."device_lock_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_model_variants_global_unique" ON "public"."device_model_variants" USING "btree" ("model_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE INDEX "device_model_variants_model_idx" ON "public"."device_model_variants" USING "btree" ("model_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "device_model_variants_org_unique" ON "public"."device_model_variants" USING "btree" ("organization_id", "model_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "device_models_family_idx" ON "public"."device_models" USING "btree" ("family_id") WHERE "is_active";



CREATE INDEX "device_models_lookup_idx" ON "public"."device_models" USING "btree" ("device_type_id", "brand_id", "organization_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "device_models_organization_unique" ON "public"."device_models" USING "btree" ("organization_id", "device_type_id", "brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "device_models_system_unique" ON "public"."device_models" USING "btree" ("device_type_id", "brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE INDEX "device_product_families_brand_idx" ON "public"."device_product_families" USING "btree" ("brand_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "device_product_families_global_unique" ON "public"."device_product_families" USING "btree" ("brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_product_families_org_unique" ON "public"."device_product_families" USING "btree" ("organization_id", "brand_id", "lower"("regexp_replace"(TRIM(BOTH FROM "name"), '\s+'::"text", ' '::"text", 'g'::"text"))) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "device_reception_controls_type_idx" ON "public"."device_reception_controls" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE INDEX "device_receptions_device_idx" ON "public"."device_receptions" USING "btree" ("organization_id", "device_id");



CREATE INDEX "device_receptions_organization_created_idx" ON "public"."device_receptions" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "device_type_diagnostic_tests_type_idx" ON "public"."device_type_diagnostic_tests" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE INDEX "device_type_fields_field_idx" ON "public"."device_type_fields" USING "btree" ("field_id");



CREATE INDEX "device_type_fields_type_section_idx" ON "public"."device_type_fields" USING "btree" ("device_type_id", "section_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "device_types_global_name_unique" ON "public"."device_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "device_types_organization_name_unique" ON "public"."device_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "diagnostic_test_types_global_key_unique" ON "public"."diagnostic_test_types" USING "btree" ("key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "diagnostic_test_types_org_key_unique" ON "public"."diagnostic_test_types" USING "btree" ("organization_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "hardware_catalog_brands_global_unique" ON "public"."hardware_catalog_brands" USING "btree" ("kind", "normalized_name") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "hardware_catalog_brands_org_unique" ON "public"."hardware_catalog_brands" USING "btree" ("organization_id", "kind", "normalized_name") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "hardware_catalog_brands_read_idx" ON "public"."hardware_catalog_brands" USING "btree" ("kind", "organization_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "hardware_catalog_models_global_unique" ON "public"."hardware_catalog_models" USING "btree" ("kind", "brand_id", "normalized_name") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "hardware_catalog_models_org_unique" ON "public"."hardware_catalog_models" USING "btree" ("organization_id", "kind", "brand_id", "normalized_name") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "hardware_catalog_models_read_idx" ON "public"."hardware_catalog_models" USING "btree" ("kind", "brand_id", "organization_id", "name") WHERE "is_active";



CREATE INDEX "inventory_brands_organization_active_idx" ON "public"."inventory_brands" USING "btree" ("organization_id", "is_active", "name");



CREATE INDEX "inventory_categories_active_name_idx" ON "public"."inventory_categories" USING "btree" ("is_active", "name");



CREATE INDEX "inventory_items_organization_active_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "is_active", "normalized_name");



CREATE INDEX "inventory_items_organization_brand_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "brand_id") WHERE ("brand_id" IS NOT NULL);



CREATE INDEX "inventory_items_organization_category_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "category_id");



CREATE UNIQUE INDEX "inventory_items_organization_sku_key" ON "public"."inventory_items" USING "btree" ("organization_id", "normalized_sku") WHERE ("normalized_sku" IS NOT NULL);



CREATE INDEX "inventory_items_organization_supplier_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "preferred_supplier_id") WHERE ("preferred_supplier_id" IS NOT NULL);



CREATE INDEX "inventory_movements_item_created_idx" ON "public"."inventory_movements" USING "btree" ("inventory_item_id", "created_at" DESC);



CREATE INDEX "inventory_movements_organization_created_idx" ON "public"."inventory_movements" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "localities_province_idx" ON "public"."localities" USING "btree" ("province_id", "name");



CREATE UNIQUE INDEX "localities_province_normalized_name_key" ON "public"."localities" USING "btree" ("province_id", "normalized_name");



CREATE UNIQUE INDEX "memory_capacities_global_unique" ON "public"."memory_capacities" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "memory_capacities_org_unique" ON "public"."memory_capacities" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "mobile_operators_global_unique" ON "public"."mobile_operators" USING "btree" ("lower"("name"), "country_code") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "mobile_operators_org_unique" ON "public"."mobile_operators" USING "btree" ("organization_id", "lower"("name"), "country_code") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "neighborhoods_locality_idx" ON "public"."neighborhoods" USING "btree" ("locality_id", "name");



CREATE UNIQUE INDEX "neighborhoods_locality_normalized_name_key" ON "public"."neighborhoods" USING "btree" ("locality_id", "normalized_name");



CREATE UNIQUE INDEX "notebook_keyboard_mount_types_global_unique" ON "public"."notebook_keyboard_mount_types" USING "btree" ("normalized_name") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "notebook_keyboard_mount_types_org_unique" ON "public"."notebook_keyboard_mount_types" USING "btree" ("organization_id", "normalized_name") WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "operating_systems_global_unique" ON "public"."operating_systems" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "operating_systems_org_unique" ON "public"."operating_systems" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "organizations_name_normalized_key" ON "public"."organizations" USING "btree" ("lower"("regexp_replace"(TRIM(BOTH FROM "name"), '[[:space:]]+'::"text", ' '::"text", 'g'::"text")));



COMMENT ON INDEX "public"."organizations_name_normalized_key" IS 'Impide nombres duplicados ignorando mayúsculas, minúsculas y espacios repetidos.';



CREATE INDEX "password_history_user_created_idx" ON "public"."password_history" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "profiles_organization_idx" ON "public"."profiles" USING "btree" ("organization_id");



CREATE INDEX "provinces_country_idx" ON "public"."provinces" USING "btree" ("country_id", "name");



CREATE UNIQUE INDEX "provinces_country_normalized_name_key" ON "public"."provinces" USING "btree" ("country_id", "normalized_name");



CREATE UNIQUE INDEX "reception_evidence_types_global_unique" ON "public"."reception_evidence_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "reception_evidence_types_org_unique" ON "public"."reception_evidence_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "reception_inspection_reception_idx" ON "public"."reception_inspection_items" USING "btree" ("organization_id", "reception_id");



CREATE INDEX "reception_photos_reception_idx" ON "public"."reception_photos" USING "btree" ("organization_id", "reception_id");



CREATE INDEX "repair_device_components_device_idx" ON "public"."repair_device_components" USING "btree" ("organization_id", "customer_device_id", "component_type_id");



CREATE INDEX "repair_device_diagnostics_reception_idx" ON "public"."repair_device_diagnostics" USING "btree" ("organization_id", "reception_id");



CREATE UNIQUE INDEX "service_categories_global_unique" ON "public"."service_categories" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "service_categories_org_unique" ON "public"."service_categories" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "storage_capacities_global_unique" ON "public"."storage_capacities" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "storage_capacities_org_unique" ON "public"."storage_capacities" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "suppliers_organization_active_idx" ON "public"."suppliers" USING "btree" ("organization_id", "is_active", "normalized_name");



CREATE INDEX "technical_services_category_idx" ON "public"."technical_services" USING "btree" ("service_category_id", "name") WHERE "is_active";



CREATE INDEX "user_quick_links_user_enabled_idx" ON "public"."user_quick_links" USING "btree" ("user_id", "enabled");



CREATE OR REPLACE TRIGGER "customer_device_field_values_updated_at" BEFORE UPDATE ON "public"."customer_device_field_values" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE CONSTRAINT TRIGGER "customer_device_pc_hardware_validation" AFTER INSERT OR UPDATE ON "public"."customer_device_field_values" DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "public"."validate_desktop_hardware_values"();



CREATE OR REPLACE TRIGGER "customer_devices_set_updated_at" BEFORE UPDATE ON "public"."customer_devices" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "customers_set_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "device_receptions_immutable" BEFORE DELETE OR UPDATE ON "public"."device_receptions" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_confirmed_reception_mutation"();



CREATE OR REPLACE TRIGGER "inventory_brands_protect_identity" BEFORE UPDATE ON "public"."inventory_brands" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "inventory_brands_set_updated_at" BEFORE UPDATE ON "public"."inventory_brands" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "inventory_items_protect_identity" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "inventory_items_protect_stock" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_stock_direct_change"();



CREATE OR REPLACE TRIGGER "inventory_items_set_updated_at" BEFORE UPDATE ON "public"."inventory_items" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "inventory_movements_immutable" BEFORE DELETE OR UPDATE ON "public"."inventory_movements" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_inventory_movement_mutation"();



CREATE OR REPLACE TRIGGER "organization_addresses_set_updated_at" BEFORE UPDATE ON "public"."organization_addresses" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "organizations_set_updated_at" BEFORE UPDATE ON "public"."organizations" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "profiles_audit_personal_data" AFTER UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."audit_profile_data_change"();



CREATE OR REPLACE TRIGGER "profiles_prevent_privilege_escalation" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_profile_privilege_escalation"();



CREATE OR REPLACE TRIGGER "profiles_set_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "reception_items_immutable" BEFORE DELETE OR UPDATE ON "public"."reception_inspection_items" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_confirmed_reception_mutation"();



CREATE OR REPLACE TRIGGER "suppliers_protect_identity" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "suppliers_set_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "user_quick_links_set_updated_at" BEFORE UPDATE ON "public"."user_quick_links" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_component_type_id_fkey" FOREIGN KEY ("component_type_id") REFERENCES "public"."component_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_attribute_definition_id_fkey" FOREIGN KEY ("attribute_definition_id") REFERENCES "public"."component_attribute_definitions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_customer_device_id_fkey" FOREIGN KEY ("customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_device_type_field_id_fkey" FOREIGN KEY ("device_type_field_id") REFERENCES "public"."device_type_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."device_field_options"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "customer_device_field_values_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_color_id_fkey" FOREIGN KEY ("color_id") REFERENCES "public"."device_colors"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_customer_id_organization_id_fkey" FOREIGN KEY ("customer_id", "organization_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "public"."device_product_families"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_lock_type_id_fkey" FOREIGN KEY ("lock_type_id") REFERENCES "public"."device_lock_types"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_mobile_operator_id_fkey" FOREIGN KEY ("mobile_operator_id") REFERENCES "public"."mobile_operators"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_model_id_fkey" FOREIGN KEY ("model_id") REFERENCES "public"."device_models"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_operating_system_id_fkey" FOREIGN KEY ("operating_system_id") REFERENCES "public"."operating_systems"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_type_id_fkey" FOREIGN KEY ("type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "customer_devices_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."device_model_variants"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_customer_id_organization_id_fkey" FOREIGN KEY ("customer_id", "organization_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "device_accessories_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "device_accessories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "device_brands_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "device_brands_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "device_colors_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "device_colors_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "device_field_dependencies_device_type_field_id_fkey" FOREIGN KEY ("device_type_field_id") REFERENCES "public"."device_type_fields"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "device_field_dependencies_parent_device_type_field_id_fkey" FOREIGN KEY ("parent_device_type_field_id") REFERENCES "public"."device_type_fields"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_field_id_fkey" FOREIGN KEY ("field_id") REFERENCES "public"."device_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "device_field_options_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "device_fields_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "device_fields_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "device_form_sections_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_lock_types"
    ADD CONSTRAINT "device_lock_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_lock_types"
    ADD CONSTRAINT "device_lock_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_model_id_fkey" FOREIGN KEY ("model_id") REFERENCES "public"."device_models"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "device_model_variants_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "public"."device_product_families"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "device_models_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_product_families"
    ADD CONSTRAINT "device_product_families_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "device_reception_controls_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_customer_id_organization_id_fkey" FOREIGN KEY ("customer_id", "organization_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_device_id_organization_id_fkey" FOREIGN KEY ("device_id", "organization_id") REFERENCES "public"."customer_devices"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "device_receptions_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_diagnostic_test_type_id_fkey" FOREIGN KEY ("diagnostic_test_type_id") REFERENCES "public"."diagnostic_test_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_section_id_fkey" FOREIGN KEY ("section_id") REFERENCES "public"."device_form_sections"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_field_id_fkey" FOREIGN KEY ("field_id") REFERENCES "public"."device_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "device_type_fields_section_id_fkey" FOREIGN KEY ("section_id") REFERENCES "public"."device_form_sections"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_technical_service_id_fkey" FOREIGN KEY ("technical_service_id") REFERENCES "public"."technical_services"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "device_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "device_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hardware_catalog_brands"
    ADD CONSTRAINT "hardware_catalog_brands_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hardware_catalog_brands"
    ADD CONSTRAINT "hardware_catalog_brands_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_brand_id_fkey" FOREIGN KEY ("brand_id") REFERENCES "public"."hardware_catalog_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."hardware_catalog_models"
    ADD CONSTRAINT "hardware_catalog_models_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_brands"
    ADD CONSTRAINT "inventory_brands_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_brand_organization_fk" FOREIGN KEY ("brand_id", "organization_id") REFERENCES "public"."inventory_brands"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."inventory_categories"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_items"
    ADD CONSTRAINT "inventory_items_supplier_organization_fk" FOREIGN KEY ("preferred_supplier_id", "organization_id") REFERENCES "public"."suppliers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_inventory_item_id_organization_id_fkey" FOREIGN KEY ("inventory_item_id", "organization_id") REFERENCES "public"."inventory_items"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."localities"
    ADD CONSTRAINT "localities_province_id_fkey" FOREIGN KEY ("province_id") REFERENCES "public"."provinces"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."memory_capacities"
    ADD CONSTRAINT "memory_capacities_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."memory_capacities"
    ADD CONSTRAINT "memory_capacities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."mobile_operators"
    ADD CONSTRAINT "mobile_operators_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."mobile_operators"
    ADD CONSTRAINT "mobile_operators_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_locality_id_fkey" FOREIGN KEY ("locality_id") REFERENCES "public"."localities"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."notebook_keyboard_mount_types"
    ADD CONSTRAINT "notebook_keyboard_mount_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notebook_keyboard_mount_types"
    ADD CONSTRAINT "notebook_keyboard_mount_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."operating_systems"
    ADD CONSTRAINT "operating_systems_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."operating_systems"
    ADD CONSTRAINT "operating_systems_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_locality_id_province_id_fkey" FOREIGN KEY ("locality_id", "province_id") REFERENCES "public"."localities"("id", "province_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_neighborhood_id_locality_id_fkey" FOREIGN KEY ("neighborhood_id", "locality_id") REFERENCES "public"."neighborhoods"("id", "locality_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."organization_addresses"
    ADD CONSTRAINT "organization_addresses_province_id_country_id_fkey" FOREIGN KEY ("province_id", "country_id") REFERENCES "public"."provinces"("id", "country_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."password_history"
    ADD CONSTRAINT "password_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "public"."countries"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "reception_inspection_items_reception_id_organization_id_fkey" FOREIGN KEY ("reception_id", "organization_id") REFERENCES "public"."device_receptions"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_reception_id_organization_id_fkey" FOREIGN KEY ("reception_id", "organization_id") REFERENCES "public"."device_receptions"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "reception_photos_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_attribute_definition_id_fkey" FOREIGN KEY ("attribute_definition_id") REFERENCES "public"."component_attribute_definitions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_component_id_fkey" FOREIGN KEY ("component_id") REFERENCES "public"."repair_device_components"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repair_device_component_values"
    ADD CONSTRAINT "repair_device_component_values_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "public"."component_attribute_options"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_component_type_id_fkey" FOREIGN KEY ("component_type_id") REFERENCES "public"."component_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_customer_device_id_fkey" FOREIGN KEY ("customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_components"
    ADD CONSTRAINT "repair_device_components_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_diagnostic_test_type_id_fkey" FOREIGN KEY ("diagnostic_test_type_id") REFERENCES "public"."diagnostic_test_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_reception_id_fkey" FOREIGN KEY ("reception_id") REFERENCES "public"."device_receptions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."repair_device_diagnostics"
    ADD CONSTRAINT "repair_device_diagnostics_result_type_id_fkey" FOREIGN KEY ("result_type_id") REFERENCES "public"."diagnostic_result_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_service_category_id_fkey" FOREIGN KEY ("service_category_id") REFERENCES "public"."service_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."account_deletion_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_deletion_requests_self_select" ON "public"."account_deletion_requests" FOR SELECT TO "authenticated" USING ((("target_user_id" = "auth"."uid"()) OR ("requested_by" = "auth"."uid"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("subject_type" = 'ORGANIZATION'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'OWNER'::"public"."app_role") AND ("p"."status" = 'ACTIVE'::"public"."profile_status") AND ("p"."organization_id" = "account_deletion_requests"."organization_id")))))));



ALTER TABLE "public"."audit_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_events_select" ON "public"."audit_events" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role"))));



ALTER TABLE "public"."auth_rate_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."component_attribute_definitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_attribute_definitions_read" ON "public"."component_attribute_definitions" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."component_attribute_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_attribute_options_read" ON "public"."component_attribute_options" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."component_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_types_read" ON "public"."component_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."countries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "countries_read" ON "public"."countries" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."customer_device_field_values" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_field_values_read" ON "public"."customer_device_field_values" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."customer_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_devices_select" ON "public"."customer_devices" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



CREATE POLICY "customer_links_delete" ON "public"."customer_user_links" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"()));



CREATE POLICY "customer_links_insert" ON "public"."customer_user_links" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"() AND ("created_by" = "auth"."uid"())));



CREATE POLICY "customer_links_select" ON "public"."customer_user_links" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR ("public"."current_organization_is_active"() AND (("auth_user_id" = "auth"."uid"()) OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_setup_completed"())))));



ALTER TABLE "public"."customer_user_links" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers_insert" ON "public"."customers" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"()));



CREATE POLICY "customers_select" ON "public"."customers" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"() AND (("public"."current_app_role"() = 'OWNER'::"public"."app_role") OR (EXISTS ( SELECT 1
   FROM "public"."customer_user_links" "l"
  WHERE (("l"."customer_id" = "customers"."id") AND ("l"."auth_user_id" = "auth"."uid"()))))))));



CREATE POLICY "customers_update" ON "public"."customers" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"())) WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND "public"."current_organization_is_active"() AND "public"."current_organization_setup_completed"()));



ALTER TABLE "public"."device_accessories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_accessories_read" ON "public"."device_accessories" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_brands_select" ON "public"."device_brands" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_colors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_colors_read_owner" ON "public"."device_colors" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_field_dependencies" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_field_dependencies_read" ON "public"."device_field_dependencies" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_field_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_field_options_read" ON "public"."device_field_options" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_fields" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_fields_read" ON "public"."device_fields" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_form_sections" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_form_sections_read" ON "public"."device_form_sections" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_lock_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_lock_types_read" ON "public"."device_lock_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_model_variants" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_model_variants_read" ON "public"."device_model_variants" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_models" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_models_read_owner" ON "public"."device_models" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_product_families" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_product_families_read" ON "public"."device_product_families" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."device_reception_controls" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_reception_controls_read" ON "public"."device_reception_controls" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."device_types" "t"
  WHERE (("t"."id" = "device_reception_controls"."device_type_id") AND (("t"."organization_id" IS NULL) OR ("t"."organization_id" = "public"."current_organization_id"()))))));



ALTER TABLE "public"."device_receptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_receptions_select" ON "public"."device_receptions" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."device_type_diagnostic_tests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_diagnostic_tests_read" ON "public"."device_type_diagnostic_tests" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_type_fields" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_fields_read" ON "public"."device_type_fields" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."device_types" "t"
  WHERE (("t"."id" = "device_type_fields"."device_type_id") AND (("t"."organization_id" IS NULL) OR ("t"."organization_id" = "public"."current_organization_id"()))))));



ALTER TABLE "public"."device_type_services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_services_read" ON "public"."device_type_services" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_types_select" ON "public"."device_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."diagnostic_result_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "diagnostic_result_types_read" ON "public"."diagnostic_result_types" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."diagnostic_test_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "diagnostic_test_types_read" ON "public"."diagnostic_test_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."hardware_catalog_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hardware_catalog_brands_read" ON "public"."hardware_catalog_brands" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."hardware_catalog_models" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hardware_catalog_models_read" ON "public"."hardware_catalog_models" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."inventory_brands" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_brands_insert" ON "public"."inventory_brands" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "inventory_brands_select" ON "public"."inventory_brands" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "inventory_brands_update" ON "public"."inventory_brands" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."inventory_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_categories_select" ON "public"."inventory_categories" FOR SELECT TO "authenticated" USING (("is_active" OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role")));



ALTER TABLE "public"."inventory_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_items_insert" ON "public"."inventory_items" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"()) AND ("current_stock" = (0)::numeric)));



CREATE POLICY "inventory_items_select" ON "public"."inventory_items" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "inventory_items_update" ON "public"."inventory_items" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."inventory_movements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_movements_select" ON "public"."inventory_movements" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



ALTER TABLE "public"."localities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "localities_read" ON "public"."localities" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."memory_capacities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "memory_capacities_read" ON "public"."memory_capacities" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."mobile_operators" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mobile_operators_read" ON "public"."mobile_operators" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."neighborhoods" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "neighborhoods_read" ON "public"."neighborhoods" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."notebook_keyboard_mount_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notebook_keyboard_mount_types_read" ON "public"."notebook_keyboard_mount_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."operating_systems" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operating_systems_read" ON "public"."operating_systems" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."organization_addresses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organization_addresses_insert" ON "public"."organization_addresses" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."status" = 'ACTIVE'::"public"."profile_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "organization_addresses"."organization_id") AND ("o"."status" = 'ACTIVE'::"public"."organization_status"))))));



CREATE POLICY "organization_addresses_select" ON "public"."organization_addresses" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role"))));



CREATE POLICY "organization_addresses_update" ON "public"."organization_addresses" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."status" = 'ACTIVE'::"public"."profile_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "organization_addresses"."organization_id") AND ("o"."status" = 'ACTIVE'::"public"."organization_status")))))) WITH CHECK ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND (EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."status" = 'ACTIVE'::"public"."profile_status")))) AND (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "organization_addresses"."organization_id") AND ("o"."status" = 'ACTIVE'::"public"."organization_status"))))));



ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "organizations_select" ON "public"."organizations" FOR SELECT TO "authenticated" USING ((("id" = "public"."current_organization_id"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role")));



ALTER TABLE "public"."password_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND ("organization_id" = "public"."current_organization_id"()))));



CREATE POLICY "profiles_update_self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."provinces" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "provinces_read" ON "public"."provinces" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."reception_evidence_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_evidence_types_read" ON "public"."reception_evidence_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."reception_inspection_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_items_select" ON "public"."reception_inspection_items" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."reception_photos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_photos_select" ON "public"."reception_photos" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."repair_device_component_values" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "repair_device_component_values_read" ON "public"."repair_device_component_values" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."repair_device_components" "c"
  WHERE (("c"."id" = "repair_device_component_values"."component_id") AND ("c"."organization_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."repair_device_components" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "repair_device_components_read" ON "public"."repair_device_components" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."repair_device_diagnostics" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "repair_device_diagnostics_read" ON "public"."repair_device_diagnostics" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role")));



ALTER TABLE "public"."service_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_categories_read" ON "public"."service_categories" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."storage_capacities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storage_capacities_read" ON "public"."storage_capacities" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "suppliers_insert" ON "public"."suppliers" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "suppliers_select" ON "public"."suppliers" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "suppliers_update" ON "public"."suppliers" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."technical_services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "technical_services_read" ON "public"."technical_services" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."user_quick_links" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_quick_links_delete_own" ON "public"."user_quick_links" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_insert_own" ON "public"."user_quick_links" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_select_own" ON "public"."user_quick_links" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_update_own" ON "public"."user_quick_links" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON TYPE "public"."inventory_movement_type" TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_create_organization"("name" "text", "slug" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_log_organization_event"("p_organization_id" "uuid", "p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_organization_status"("p_organization_id" "uuid", "p_status" "public"."organization_status", "p_confirmation" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_update_profile_access"("p_user_id" "uuid", "p_role" "public"."app_role", "p_status" "public"."profile_status", "p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_inventory_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_inventory_owner"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."assert_reception_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assert_reception_owner"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assert_reception_owner"() TO "service_role";



GRANT ALL ON FUNCTION "public"."audit_profile_data_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."audit_profile_data_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."audit_profile_data_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_my_pending_deletion"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_my_pending_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_my_pending_deletion"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_initial_organization_setup"("p_name" "text", "p_trade_name" "text", "p_logo_path" "text", "p_phone" "text", "p_contact_email" "text", "p_address" "text", "p_locality" "text", "p_province" "text", "p_description" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_password_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_password_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_password_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_device_reception"("p_customer_id" "uuid", "p_device_id" "uuid", "p_reported_problem" "text", "p_observations" "text", "p_inspection" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") TO "service_role";



GRANT ALL ON TABLE "public"."device_brands" TO "anon";
GRANT ALL ON TABLE "public"."device_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."device_brands" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_brand"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_brand"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_brand"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_brand_for_type"("p_name" "text", "p_type_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."device_colors" TO "anon";
GRANT ALL ON TABLE "public"."device_colors" TO "authenticated";
GRANT ALL ON TABLE "public"."device_colors" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_color"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_color"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_color"("p_name" "text") TO "service_role";



GRANT ALL ON TABLE "public"."device_models" TO "anon";
GRANT ALL ON TABLE "public"."device_models" TO "authenticated";
GRANT ALL ON TABLE "public"."device_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_model"("p_name" "text", "p_type_id" "uuid", "p_brand_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "public"."device_types" TO "anon";
GRANT ALL ON TABLE "public"."device_types" TO "authenticated";
GRANT ALL ON TABLE "public"."device_types" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_custom_device_type"("p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_custom_device_type"("p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_custom_device_type"("p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device_dynamic_legacy"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_device_with_catalog"("p_customer_id" "uuid", "p_type_id" "uuid", "p_brand_id" "uuid", "p_model_id" "uuid", "p_model" "text", "p_year" "text", "p_color" "text", "p_serial_number" "text", "p_imei_1" "text", "p_imei_2" "text", "p_attributes" "jsonb", "p_memories" "jsonb", "p_storage_units" "jsonb", "p_accessories" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "service_role";



GRANT ALL ON TABLE "public"."hardware_catalog_models" TO "anon";
GRANT ALL ON TABLE "public"."hardware_catalog_models" TO "authenticated";
GRANT ALL ON TABLE "public"."hardware_catalog_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_hardware_catalog_model"("p_kind" "text", "p_brand_id" "uuid", "p_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reception_customer"("p_first_name" "text", "p_last_name" "text", "p_phone" "text", "p_contact_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_app_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_organization_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_organization_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_organization_is_active"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_organization_is_active"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_is_active"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_organization_setup_completed"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_organization_setup_completed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_organization_setup_completed"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_due_account_deletions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_due_account_deletions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_initial_organization_setup"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_initial_organization_setup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."finalize_initial_organization_setup"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_my_pending_deletion"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_pending_deletion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_pending_deletion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_inventory_owner_access"("p_organization_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_audit_event"("p_event_type" "text", "p_entity_type" "text", "p_entity_id" "uuid", "p_metadata" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."mark_deletion_auth_cleanup"("p_request_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_confirmed_reception_mutation"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_confirmed_reception_mutation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_confirmed_reception_mutation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_inventory_movement_mutation"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_inventory_movement_mutation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_inventory_stock_direct_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_inventory_stock_direct_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_escalation"() TO "anon";
GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_escalation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prevent_profile_privilege_escalation"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."protect_inventory_record_identity"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."protect_inventory_record_identity"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."quick_link_url_allowed"("p_service" "text", "p_url" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_inventory_movement"("p_inventory_item_id" "uuid", "p_movement_type" "public"."inventory_movement_type", "p_quantity" numeric, "p_reason" "text", "p_unit_cost" numeric, "p_reference_type" "text", "p_reference_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_reception_photo"("p_reception_id" "uuid", "p_storage_path" "text", "p_description" "text", "p_inspection_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."replace_own_quick_links"("p_links" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_customer_account_deletion"("p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."request_organization_deletion"("p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_organization_deletion"("p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_organization_deletion"("p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_auth_rate_limit"("p_action" "text", "p_key_hash" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_one"("p_legal_name" "text", "p_commercial_name" "text", "p_logo_path" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_three"("p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean, "p_floor" "text", "p_apartment" "text", "p_postal_code" "text", "p_reference" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_initial_organization_step_two"("p_phone" "text", "p_contact_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_own_superadmin_profile"("p_first_name" "text", "p_last_name" "text", "p_display_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_owner_organization_settings"("p_name" "text", "p_logo_path" "text", "p_phone" "text", "p_phone_country_code" "text", "p_phone_calling_code" "text", "p_phone_national_number" "text", "p_contact_email" "text", "p_country_id" "text", "p_province_id" "text", "p_locality_id" "text", "p_neighborhood_id" "text", "p_street" "text", "p_street_number" integer, "p_without_number" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_desktop_hardware_values"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_desktop_hardware_values"() TO "service_role";



GRANT ALL ON TABLE "public"."account_deletion_requests" TO "service_role";
GRANT SELECT ON TABLE "public"."account_deletion_requests" TO "authenticated";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."audit_events" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."audit_events" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_events" TO "service_role";



GRANT ALL ON TABLE "public"."auth_rate_limits" TO "service_role";



GRANT ALL ON TABLE "public"."component_attribute_definitions" TO "anon";
GRANT ALL ON TABLE "public"."component_attribute_definitions" TO "authenticated";
GRANT ALL ON TABLE "public"."component_attribute_definitions" TO "service_role";



GRANT ALL ON TABLE "public"."component_attribute_options" TO "anon";
GRANT ALL ON TABLE "public"."component_attribute_options" TO "authenticated";
GRANT ALL ON TABLE "public"."component_attribute_options" TO "service_role";



GRANT ALL ON TABLE "public"."component_types" TO "anon";
GRANT ALL ON TABLE "public"."component_types" TO "authenticated";
GRANT ALL ON TABLE "public"."component_types" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."countries" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."countries" TO "authenticated";
GRANT ALL ON TABLE "public"."countries" TO "service_role";



GRANT ALL ON TABLE "public"."customer_device_field_values" TO "anon";
GRANT ALL ON TABLE "public"."customer_device_field_values" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_field_values" TO "service_role";



GRANT ALL ON TABLE "public"."customer_devices" TO "anon";
GRANT ALL ON TABLE "public"."customer_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_devices" TO "service_role";



GRANT ALL ON TABLE "public"."customer_user_links" TO "anon";
GRANT ALL ON TABLE "public"."customer_user_links" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_user_links" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."device_accessories" TO "anon";
GRANT ALL ON TABLE "public"."device_accessories" TO "authenticated";
GRANT ALL ON TABLE "public"."device_accessories" TO "service_role";



GRANT ALL ON TABLE "public"."device_field_dependencies" TO "anon";
GRANT ALL ON TABLE "public"."device_field_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."device_field_dependencies" TO "service_role";



GRANT ALL ON TABLE "public"."device_field_options" TO "anon";
GRANT ALL ON TABLE "public"."device_field_options" TO "authenticated";
GRANT ALL ON TABLE "public"."device_field_options" TO "service_role";



GRANT ALL ON TABLE "public"."device_fields" TO "anon";
GRANT ALL ON TABLE "public"."device_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."device_fields" TO "service_role";



GRANT ALL ON TABLE "public"."device_form_sections" TO "anon";
GRANT ALL ON TABLE "public"."device_form_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."device_form_sections" TO "service_role";



GRANT ALL ON TABLE "public"."device_lock_types" TO "anon";
GRANT ALL ON TABLE "public"."device_lock_types" TO "authenticated";
GRANT ALL ON TABLE "public"."device_lock_types" TO "service_role";



GRANT ALL ON TABLE "public"."device_model_variants" TO "anon";
GRANT ALL ON TABLE "public"."device_model_variants" TO "authenticated";
GRANT ALL ON TABLE "public"."device_model_variants" TO "service_role";



GRANT ALL ON TABLE "public"."device_product_families" TO "anon";
GRANT ALL ON TABLE "public"."device_product_families" TO "authenticated";
GRANT ALL ON TABLE "public"."device_product_families" TO "service_role";



GRANT ALL ON TABLE "public"."device_reception_controls" TO "anon";
GRANT ALL ON TABLE "public"."device_reception_controls" TO "authenticated";
GRANT ALL ON TABLE "public"."device_reception_controls" TO "service_role";



GRANT ALL ON TABLE "public"."device_receptions" TO "anon";
GRANT ALL ON TABLE "public"."device_receptions" TO "authenticated";
GRANT ALL ON TABLE "public"."device_receptions" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "anon";
GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_fields" TO "anon";
GRANT ALL ON TABLE "public"."device_type_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_fields" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_services" TO "anon";
GRANT ALL ON TABLE "public"."device_type_services" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_services" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "anon";
GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "anon";
GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "service_role";



GRANT ALL ON TABLE "public"."hardware_catalog_brands" TO "anon";
GRANT ALL ON TABLE "public"."hardware_catalog_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."hardware_catalog_brands" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_brands" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_brands" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_categories" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_items" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."inventory_items" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_items" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_movements" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."inventory_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_movements" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."localities" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."localities" TO "authenticated";
GRANT ALL ON TABLE "public"."localities" TO "service_role";



GRANT ALL ON TABLE "public"."memory_capacities" TO "anon";
GRANT ALL ON TABLE "public"."memory_capacities" TO "authenticated";
GRANT ALL ON TABLE "public"."memory_capacities" TO "service_role";



GRANT ALL ON TABLE "public"."mobile_operators" TO "anon";
GRANT ALL ON TABLE "public"."mobile_operators" TO "authenticated";
GRANT ALL ON TABLE "public"."mobile_operators" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."neighborhoods" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."neighborhoods" TO "authenticated";
GRANT ALL ON TABLE "public"."neighborhoods" TO "service_role";



GRANT ALL ON TABLE "public"."notebook_keyboard_mount_types" TO "anon";
GRANT ALL ON TABLE "public"."notebook_keyboard_mount_types" TO "authenticated";
GRANT ALL ON TABLE "public"."notebook_keyboard_mount_types" TO "service_role";



GRANT ALL ON TABLE "public"."operating_systems" TO "anon";
GRANT ALL ON TABLE "public"."operating_systems" TO "authenticated";
GRANT ALL ON TABLE "public"."operating_systems" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organization_addresses" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organization_addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_addresses" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."password_history" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."provinces" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."provinces" TO "authenticated";
GRANT ALL ON TABLE "public"."provinces" TO "service_role";



GRANT ALL ON TABLE "public"."reception_evidence_types" TO "anon";
GRANT ALL ON TABLE "public"."reception_evidence_types" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_evidence_types" TO "service_role";



GRANT ALL ON TABLE "public"."reception_inspection_items" TO "anon";
GRANT ALL ON TABLE "public"."reception_inspection_items" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_inspection_items" TO "service_role";



GRANT ALL ON TABLE "public"."reception_photos" TO "anon";
GRANT ALL ON TABLE "public"."reception_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_photos" TO "service_role";



GRANT ALL ON TABLE "public"."repair_device_component_values" TO "anon";
GRANT ALL ON TABLE "public"."repair_device_component_values" TO "authenticated";
GRANT ALL ON TABLE "public"."repair_device_component_values" TO "service_role";



GRANT ALL ON TABLE "public"."repair_device_components" TO "anon";
GRANT ALL ON TABLE "public"."repair_device_components" TO "authenticated";
GRANT ALL ON TABLE "public"."repair_device_components" TO "service_role";



GRANT ALL ON TABLE "public"."repair_device_diagnostics" TO "anon";
GRANT ALL ON TABLE "public"."repair_device_diagnostics" TO "authenticated";
GRANT ALL ON TABLE "public"."repair_device_diagnostics" TO "service_role";



GRANT ALL ON TABLE "public"."service_categories" TO "anon";
GRANT ALL ON TABLE "public"."service_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."service_categories" TO "service_role";



GRANT ALL ON TABLE "public"."storage_capacities" TO "anon";
GRANT ALL ON TABLE "public"."storage_capacities" TO "authenticated";
GRANT ALL ON TABLE "public"."storage_capacities" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."suppliers" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."technical_services" TO "anon";
GRANT ALL ON TABLE "public"."technical_services" TO "authenticated";
GRANT ALL ON TABLE "public"."technical_services" TO "service_role";



GRANT ALL ON TABLE "public"."user_quick_links" TO "anon";
GRANT ALL ON TABLE "public"."user_quick_links" TO "authenticated";
GRANT ALL ON TABLE "public"."user_quick_links" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







