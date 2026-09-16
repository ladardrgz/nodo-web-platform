


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


CREATE OR REPLACE FUNCTION "public"."confirmar_recepcion_dispositivo"("p_dispositivo_cliente_id" "uuid", "p_problema_informado" "text", "p_observaciones" "text", "p_resultados" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid := public.assert_reception_owner(); v_id uuid; v_item jsonb;
begin
  if jsonb_typeof(p_resultados) <> 'array' then raise exception 'INVALID_INSPECTION'; end if;
  insert into public.recepciones_dispositivos(fk_organizacion_id, fk_dispositivo_cliente_id, problema_informado, observaciones, puntaje_condicion, condicion_calculada, snapshot_ingreso, created_by)
  values (v_org, p_dispositivo_cliente_id, regexp_replace(btrim(p_problema_informado), '\\s+', ' ', 'g'), nullif(regexp_replace(btrim(coalesce(p_observaciones, '')), '\\s+', ' ', 'g'), ''), 0, 'No comprobable', '{}'::jsonb, auth.uid()) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_resultados) loop
    insert into public.resultados_control_recepcion(fk_recepcion_dispositivo_id, fk_control_recepcion_dispositivo_id, condicion, observacion)
    select v_id, c.id,
      case coalesce(v_item->>'condition','') when 'NOT_WORKING' then 'NO_FUNCIONA' when 'NOT_VERIFIABLE' then 'NO_COMPROBABLE' else 'BUENO' end,
      nullif(btrim(v_item->>'observation'), '')
    from public.controles_recepcion_dispositivo c
    join public.tipos_dispositivo_controles_recepcion tc on tc.fk_control_recepcion_dispositivo_id = c.id and tc.activo
    join public.dispositivos_clientes d on d.id = p_dispositivo_cliente_id and d.fk_tipo_dispositivo_id = tc.fk_tipo_dispositivo_id and d.fk_organizacion_id = v_org
    where c.clave = v_item->>'key'
    on conflict (fk_recepcion_dispositivo_id, fk_control_recepcion_dispositivo_id) do nothing;
  end loop;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata) values (v_org, auth.uid(), 'RECEPCION_DISPOSITIVO_CONFIRMADA', 'RECEPCION_DISPOSITIVO', v_id, '{}'::jsonb);
  return v_id;
end $$;


ALTER FUNCTION "public"."confirmar_recepcion_dispositivo"("p_dispositivo_cliente_id" "uuid", "p_problema_informado" "text", "p_observaciones" "text", "p_resultados" "jsonb") OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."normalizar_nombre_catalogo"("p_valor" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    SET "search_path" TO ''
    AS $$
  select lower(regexp_replace(btrim(p_valor), '\\s+', ' ', 'g'))
$$;


ALTER FUNCTION "public"."normalizar_nombre_catalogo"("p_valor" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."device_accessories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "activo" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_accesorios_dispositivo_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_accesorios_dispositivo_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 120)))
);


ALTER TABLE "public"."device_accessories" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_accesorio_dispositivo"("p_nombre" "text") RETURNS "public"."device_accessories"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_accesorio public.accesorios_dispositivo;
begin
  if char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_ACCESSORY'; end if;
  select * into v_accesorio from public.accesorios_dispositivo where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_accesorio; end if;
  insert into public.accesorios_dispositivo(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid()) on conflict on constraint uq_accesorios_dispositivo_nombre_alcance do update set updated_at=now() returning * into v_accesorio;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'ACCESORIO_DISPOSITIVO_CREADO','ACCESORIO_DISPOSITIVO',v_accesorio.id,'{}');
  return v_accesorio;
end $$;


ALTER FUNCTION "public"."crear_accesorio_dispositivo"("p_nombre" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_colors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "alcance" "text" DEFAULT 'GLOBAL'::"text" NOT NULL,
    "fk_organizacion_id" "uuid",
    CONSTRAINT "ck_colores_dispositivo_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_colores_dispositivo_nombre" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 80)))
);


ALTER TABLE "public"."device_colors" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_color_dispositivo"("p_nombre" "text") RETURNS "public"."device_colors"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_color public.colores_dispositivo;
begin
  if char_length(v_nombre) not between 2 and 80 then raise exception 'INVALID_DEVICE_COLOR'; end if;
  select * into v_color from public.colores_dispositivo where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_color; end if;
  insert into public.colores_dispositivo(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid())
  on conflict on constraint uq_colores_dispositivo_nombre_alcance do update set updated_at=now() returning * into v_color;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'COLOR_DISPOSITIVO_CREADO','COLOR_DISPOSITIVO',v_color.id,'{}');
  return v_color;
end $$;


ALTER FUNCTION "public"."crear_color_dispositivo"("p_nombre" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_dispositivo_cliente"("p_cliente_id" "uuid", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid", "p_modelo_dispositivo_id" "uuid" DEFAULT NULL::"uuid", "p_variante_modelo_dispositivo_id" "uuid" DEFAULT NULL::"uuid", "p_color_dispositivo_id" "uuid" DEFAULT NULL::"uuid", "p_numero_serie" "text" DEFAULT NULL::"text", "p_marca_procesador_id" "uuid" DEFAULT NULL::"uuid", "p_familia_procesador_id" "uuid" DEFAULT NULL::"uuid", "p_modelo_procesador_id" "uuid" DEFAULT NULL::"uuid", "p_atributos" "jsonb" DEFAULT '{}'::"jsonb", "p_memorias" "jsonb" DEFAULT '[]'::"jsonb", "p_almacenamientos" "jsonb" DEFAULT '[]'::"jsonb", "p_accesorios" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid; v_es_pc boolean; v_par record; v_campo record; v_item jsonb; v_opcion uuid; v_categoria text; v_marca uuid; v_modelo uuid;
begin
  if jsonb_typeof(p_atributos)<>'object' or jsonb_typeof(p_memorias)<>'array' or jsonb_typeof(p_almacenamientos)<>'array' or jsonb_typeof(p_accesorios)<>'array' then raise exception 'INVALID_DEVICE_DATA'; end if;
  if not exists(select 1 from public.customers where id=p_cliente_id and organization_id=v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  select nombre_normalizado='pc' into v_es_pc from public.tipos_dispositivo where id=p_tipo_dispositivo_id and activo;
  if v_es_pc is null then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if not exists(select 1 from public.tipos_dispositivo_marcas tm join public.marcas_dispositivo m on m.id=tm.fk_marca_dispositivo_id where tm.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and tm.fk_marca_dispositivo_id=p_marca_dispositivo_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if p_modelo_dispositivo_id is not null and not exists(select 1 from public.modelos_dispositivo m where m.id=p_modelo_dispositivo_id and m.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and m.fk_marca_dispositivo_id=p_marca_dispositivo_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_variante_modelo_dispositivo_id is not null and not exists(select 1 from public.variantes_modelo_dispositivo v where v.id=p_variante_modelo_dispositivo_id and v.fk_modelo_dispositivo_id=p_modelo_dispositivo_id and v.activo) then raise exception 'INVALID_DEVICE_VARIANT'; end if;
  if p_color_dispositivo_id is not null and not exists(select 1 from public.colores_dispositivo where id=p_color_dispositivo_id and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_COLOR'; end if;
  if v_es_pc and p_color_dispositivo_id is null then raise exception 'DEVICE_COLOR_REQUIRED'; end if;
  if v_es_pc and nullif(btrim(coalesce(p_numero_serie,'')),'') is not null then raise exception 'PC_SERIAL_NOT_ALLOWED'; end if;
  if v_es_pc and (p_marca_procesador_id is null or p_familia_procesador_id is null or p_modelo_procesador_id is null) then raise exception 'PROCESSOR_REQUIRED'; end if;
  if p_modelo_procesador_id is not null and not exists(select 1 from public.modelos_procesador mp join public.familias_procesador fp on fp.id=mp.fk_familia_procesador_id where mp.id=p_modelo_procesador_id and fp.id=p_familia_procesador_id and fp.fk_marca_procesador_id=p_marca_procesador_id and mp.activo and fp.activo and (mp.alcance='GLOBAL' or mp.fk_organizacion_id=v_org)) then raise exception 'INVALID_PROCESSOR'; end if;

  if v_es_pc then
    if coalesce(p_atributos->>'case_fan_count','') !~ '^([0-9]|[1-4][0-9]|50)$' then raise exception 'INVALID_CASE_FAN_COUNT'; end if;
    if coalesce(p_atributos->>'case_has_original_power_supply','') not in ('true','false') then raise exception 'INVALID_POWER_SUPPLY_MODE'; end if;
    if p_atributos->>'case_has_original_power_supply'='true' and char_length(btrim(coalesce(p_atributos->>'included_power_supply_name',''))) not between 2 and 200 then raise exception 'INCLUDED_POWER_SUPPLY_REQUIRED'; end if;
    if p_atributos->>'case_has_original_power_supply'='true' and (nullif(p_atributos->>'external_power_supply_brand_id','') is not null or nullif(p_atributos->>'external_power_supply_model_id','') is not null) then raise exception 'DUPLICATED_POWER_SUPPLY'; end if;
    if p_atributos->>'case_has_original_power_supply'='false' and nullif(btrim(coalesce(p_atributos->>'included_power_supply_name','')),'') is not null then raise exception 'DUPLICATED_POWER_SUPPLY'; end if;
    if coalesce(p_atributos->>'graphics_mode','') not in ('INTEGRATED','DEDICATED') then raise exception 'INVALID_GRAPHICS_MODE'; end if;
    if p_atributos->>'graphics_mode'='DEDICATED' and (nullif(p_atributos->>'gpu_brand_id','') is null or nullif(p_atributos->>'gpu_model_id','') is null) then raise exception 'DEDICATED_GPU_REQUIRED'; end if;
    if p_atributos->>'graphics_mode'='INTEGRATED' and (nullif(p_atributos->>'gpu_brand_id','') is not null or nullif(p_atributos->>'gpu_model_id','') is not null) then raise exception 'DUPLICATED_GRAPHICS'; end if;
    if coalesce(p_atributos->>'cpu_cooler_mode','') not in ('ORIGINAL','EXTERNAL') then raise exception 'INVALID_CPU_COOLER_MODE'; end if;
    if p_atributos->>'cpu_cooler_mode'='EXTERNAL' and (nullif(p_atributos->>'cpu_cooler_brand_id','') is null or nullif(p_atributos->>'cpu_cooler_model_id','') is null) then raise exception 'EXTERNAL_CPU_COOLER_REQUIRED'; end if;
    if p_atributos->>'cpu_cooler_mode'='ORIGINAL' and (nullif(p_atributos->>'cpu_cooler_brand_id','') is not null or nullif(p_atributos->>'cpu_cooler_model_id','') is not null) then raise exception 'DUPLICATED_CPU_COOLER'; end if;
    if coalesce(p_atributos->>'operating_system_kind','') not in ('WINDOWS','LINUX','MACOS','OTHER','NONE') then raise exception 'INVALID_OPERATING_SYSTEM'; end if;
    if p_atributos->>'operating_system_kind'<>'NONE' and char_length(btrim(coalesce(p_atributos->>'operating_system_version',''))) not between 2 and 120 then raise exception 'OPERATING_SYSTEM_VERSION_REQUIRED'; end if;
    if p_atributos->>'operating_system_kind'='NONE' and nullif(btrim(coalesce(p_atributos->>'operating_system_version','')),'') is not null then raise exception 'INVALID_OPERATING_SYSTEM'; end if;
    if coalesce(p_atributos->>'has_wifi','') not in ('true','false') then raise exception 'INVALID_WIFI'; end if;
    if p_atributos->>'has_wifi'='true' and coalesce(p_atributos->>'wifi_mode','') not in ('INTEGRATED','EXTERNAL') then raise exception 'INVALID_WIFI_MODE'; end if;
    if p_atributos->>'wifi_mode'='EXTERNAL' and (nullif(p_atributos->>'wifi_brand_id','') is null or nullif(p_atributos->>'wifi_model_id','') is null) then raise exception 'EXTERNAL_WIFI_REQUIRED'; end if;
    if (p_atributos->>'has_wifi'='false' or p_atributos->>'wifi_mode'='INTEGRATED') and (nullif(p_atributos->>'wifi_brand_id','') is not null or nullif(p_atributos->>'wifi_model_id','') is not null) then raise exception 'DUPLICATED_WIFI'; end if;
    if coalesce(p_atributos->>'has_optical_drive','') not in ('true','false') then raise exception 'INVALID_OPTICAL_DRIVE'; end if;
  end if;

  -- Comprueba todos los pares marca/modelo de componentes sin confiar en IDs del cliente.
  for v_par in select * from (values
    ('GABINETE','case_brand_id','case_model_id'),('FUENTE_ALIMENTACION','external_power_supply_brand_id','external_power_supply_model_id'),
    ('PLACA_MADRE','motherboard_brand_id','motherboard_model_id'),('TARJETA_GRAFICA','gpu_brand_id','gpu_model_id'),
    ('COOLER_PROCESADOR','cpu_cooler_brand_id','cpu_cooler_model_id'),('ADAPTADOR_WIFI','wifi_brand_id','wifi_model_id')
  ) x(categoria,clave_marca,clave_modelo) loop
    v_marca:=nullif(p_atributos->>v_par.clave_marca,'')::uuid; v_modelo:=nullif(p_atributos->>v_par.clave_modelo,'')::uuid;
    if v_modelo is not null and v_marca is null then raise exception 'INVALID_COMPONENT_MODEL'; end if;
    if v_marca is not null and not exists(select 1 from public.marcas_componente m join public.categorias_componente_marcas cm on cm.fk_marca_componente_id=m.id join public.categorias_componente c on c.id=cm.fk_categoria_componente_id where m.id=v_marca and c.clave=v_par.categoria and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_COMPONENT_BRAND'; end if;
    if v_modelo is not null and not exists(select 1 from public.modelos_componente m join public.categorias_componente c on c.id=m.fk_categoria_componente_id where m.id=v_modelo and m.fk_marca_componente_id=v_marca and c.clave=v_par.categoria and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_COMPONENT_MODEL'; end if;
  end loop;

  insert into public.dispositivos_clientes(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,fk_variante_modelo_dispositivo_id,fk_color_dispositivo_id,numero_serie,created_by)
  values(v_org,p_cliente_id,p_tipo_dispositivo_id,p_marca_dispositivo_id,p_modelo_dispositivo_id,p_variante_modelo_dispositivo_id,p_color_dispositivo_id,nullif(btrim(p_numero_serie),''),auth.uid()) returning id into v_id;
  if p_modelo_procesador_id is not null then insert into public.procesadores_dispositivos(fk_dispositivo_cliente_id,fk_modelo_procesador_id) values(v_id,p_modelo_procesador_id); end if;

  for v_par in select key,value from jsonb_each_text(p_atributos) loop
    if v_par.value='' then continue; end if;
    select tc.id,c.tipo_campo,c.clave_fuente_datos into v_campo from public.tipos_dispositivo_campos tc join public.campos_dispositivo c on c.id=tc.fk_campo_dispositivo_id where tc.fk_tipo_dispositivo_id=p_tipo_dispositivo_id and tc.activo and c.activo and c.clave=v_par.key;
    if not found then raise exception 'INVALID_DEVICE_FIELD'; end if;
    if v_campo.tipo_campo in ('SELECT','RADIO') and v_campo.clave_fuente_datos is null then
      select o.id into v_opcion from public.opciones_campo_dispositivo o where o.fk_campo_dispositivo_id=(select fk_campo_dispositivo_id from public.tipos_dispositivo_campos where id=v_campo.id) and o.valor=v_par.value and o.activo;
      if v_opcion is null then raise exception 'INVALID_DEVICE_FIELD_OPTION'; end if;
      insert into public.valores_campos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,fk_opcion_campo_dispositivo_id) values(v_id,v_campo.id,v_opcion);
    elsif v_campo.tipo_campo='NUMBER' then
      insert into public.valores_campos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,valor_numero) values(v_id,v_campo.id,v_par.value::numeric);
    else
      insert into public.valores_campos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,valor_texto) values(v_id,v_campo.id,btrim(v_par.value));
    end if;
  end loop;

  for v_item in select value from jsonb_array_elements(p_memorias) loop
    if coalesce(v_item->>'capacity','') !~ '^[1-9][0-9]{0,3}$' or coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]{0,2}$' then raise exception 'INVALID_MEMORY'; end if;
    insert into public.memoria_ram_dispositivo(fk_dispositivo_cliente_id,capacidad_gb,cantidad,soldada) values(v_id,(v_item->>'capacity')::integer,(v_item->>'quantity')::smallint,coalesce((v_item->>'soldered')::boolean,false));
  end loop;
  for v_item in select value from jsonb_array_elements(p_almacenamientos) loop
    if coalesce(v_item->>'capacity','') !~ '^[1-9][0-9]{0,6}$' or coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]{0,2}$' then raise exception 'INVALID_STORAGE'; end if;
    if not exists(select 1 from public.tipos_almacenamiento where id=(v_item->>'type')::uuid and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org)) then raise exception 'INVALID_STORAGE_TYPE'; end if;
    insert into public.almacenamientos_dispositivo(fk_dispositivo_cliente_id,fk_tipo_almacenamiento_id,capacidad_gb,cantidad) values(v_id,(v_item->>'type')::uuid,(v_item->>'capacity')::integer,(v_item->>'quantity')::smallint);
  end loop;
  for v_item in select value from jsonb_array_elements(p_accesorios) loop
    if not exists(select 1 from public.accesorios_dispositivo where id=(v_item#>>'{}')::uuid and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org)) then raise exception 'INVALID_ACCESSORY'; end if;
    insert into public.dispositivos_clientes_accesorios(fk_dispositivo_cliente_id,fk_accesorio_dispositivo_id) values(v_id,(v_item#>>'{}')::uuid) on conflict do nothing;
  end loop;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DISPOSITIVO_CLIENTE_CREADO','DISPOSITIVO_CLIENTE',v_id,jsonb_build_object('modelo_procesador_id',p_modelo_procesador_id,'memorias',jsonb_array_length(p_memorias),'almacenamientos',jsonb_array_length(p_almacenamientos),'accesorios',jsonb_array_length(p_accesorios)));
  return v_id;
end $_$;


ALTER FUNCTION "public"."crear_dispositivo_cliente"("p_cliente_id" "uuid", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid", "p_modelo_dispositivo_id" "uuid", "p_variante_modelo_dispositivo_id" "uuid", "p_color_dispositivo_id" "uuid", "p_numero_serie" "text", "p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_modelo_procesador_id" "uuid", "p_atributos" "jsonb", "p_memorias" "jsonb", "p_almacenamientos" "jsonb", "p_accesorios" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "activo" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_marcas_componente_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_marcas_componente_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 120)))
);


ALTER TABLE "public"."component_brands" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_marca_componente"("p_categoria" "text", "p_nombre" "text") RETURNS "public"."component_brands"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_categoria uuid; v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_marca public.marcas_componente;
begin
  select id into v_categoria from public.categorias_componente where clave=upper(btrim(p_categoria)) and activo;
  if v_categoria is null or char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_COMPONENT_BRAND'; end if;
  select * into v_marca from public.marcas_componente where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if not found then
    insert into public.marcas_componente(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid())
    on conflict on constraint uq_marcas_componente_nombre_alcance do update set updated_at=now() returning * into v_marca;
  end if;
  insert into public.categorias_componente_marcas values(v_categoria,v_marca.id,now()) on conflict do nothing;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MARCA_COMPONENTE_VINCULADA','MARCA_COMPONENTE',v_marca.id,jsonb_build_object('categoria',upper(btrim(p_categoria))));
  return v_marca;
end $$;


ALTER FUNCTION "public"."crear_marca_componente"("p_categoria" "text", "p_nombre" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_marcas_dispositivo_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_marcas_dispositivo_nombre" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 80)))
);


ALTER TABLE "public"."device_brands" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_marca_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid") RETURNS "public"."device_brands"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid := public.assert_reception_owner(); v_marca public.marcas_dispositivo;
begin
  if not exists (select 1 from public.tipos_dispositivo where id = p_tipo_dispositivo_id and activo) then raise exception 'INVALID_DEVICE_TYPE'; end if;
  insert into public.marcas_dispositivo(nombre, alcance, fk_organizacion_id, created_by)
  values (regexp_replace(btrim(p_nombre), '\\s+', ' ', 'g'), 'ORGANIZACION', v_org, auth.uid())
  on conflict (nombre_normalizado, fk_organizacion_id) do update set updated_at = now()
  returning * into v_marca;
  insert into public.tipos_dispositivo_marcas(fk_tipo_dispositivo_id, fk_marca_dispositivo_id)
  values (p_tipo_dispositivo_id, v_marca.id) on conflict do nothing;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_org, auth.uid(), 'MARCA_DISPOSITIVO_CREADA', 'MARCA_DISPOSITIVO', v_marca.id, jsonb_build_object('tipo_dispositivo_id', p_tipo_dispositivo_id));
  return v_marca;
end $$;


ALTER FUNCTION "public"."crear_marca_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_categoria_componente_id" "uuid" NOT NULL,
    "fk_marca_componente_id" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "activo" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_modelos_componente_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_modelos_componente_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 200)))
);


ALTER TABLE "public"."component_models" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_modelo_componente"("p_categoria" "text", "p_marca_componente_id" "uuid", "p_nombre" "text") RETURNS "public"."component_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_categoria uuid; v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_modelo public.modelos_componente;
begin
  select c.id into v_categoria from public.categorias_componente c join public.categorias_componente_marcas cm on cm.fk_categoria_componente_id=c.id join public.marcas_componente m on m.id=cm.fk_marca_componente_id where c.clave=upper(btrim(p_categoria)) and c.activo and m.id=p_marca_componente_id and m.activo and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org);
  if v_categoria is null or char_length(v_nombre) not between 2 and 200 then raise exception 'INVALID_COMPONENT_MODEL'; end if;
  select * into v_modelo from public.modelos_componente where fk_categoria_componente_id=v_categoria and fk_marca_componente_id=p_marca_componente_id and nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_modelo; end if;
  insert into public.modelos_componente(fk_categoria_componente_id,fk_marca_componente_id,nombre,alcance,fk_organizacion_id,created_by) values(v_categoria,p_marca_componente_id,v_nombre,'ORGANIZACION',v_org,auth.uid())
  on conflict on constraint uq_modelos_componente_nombre_alcance do update set updated_at=now() returning * into v_modelo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MODELO_COMPONENTE_CREADO','MODELO_COMPONENTE',v_modelo.id,jsonb_build_object('categoria',upper(btrim(p_categoria)),'marca_componente_id',p_marca_componente_id));
  return v_modelo;
end $$;


ALTER FUNCTION "public"."crear_modelo_componente"("p_categoria" "text", "p_marca_componente_id" "uuid", "p_nombre" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_tipo_dispositivo_id" "uuid" NOT NULL,
    "fk_marca_dispositivo_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_modelos_dispositivo_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_modelos_dispositivo_nombre" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120)))
);


ALTER TABLE "public"."device_models" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_modelo_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid") RETURNS "public"."device_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid := public.assert_reception_owner(); v_modelo public.modelos_dispositivo;
begin
  if not exists (select 1 from public.tipos_dispositivo_marcas tm join public.marcas_dispositivo m on m.id = tm.fk_marca_dispositivo_id where tm.fk_tipo_dispositivo_id = p_tipo_dispositivo_id and tm.fk_marca_dispositivo_id = p_marca_dispositivo_id and m.activo and (m.alcance = 'GLOBAL' or m.fk_organizacion_id = v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  insert into public.modelos_dispositivo(fk_tipo_dispositivo_id, fk_marca_dispositivo_id, nombre, alcance, fk_organizacion_id, created_by)
  values (p_tipo_dispositivo_id, p_marca_dispositivo_id, regexp_replace(btrim(p_nombre), '\\s+', ' ', 'g'), 'ORGANIZACION', v_org, auth.uid())
  on conflict (fk_tipo_dispositivo_id, fk_marca_dispositivo_id, nombre_normalizado, fk_organizacion_id) do update set updated_at = now()
  returning * into v_modelo;
  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_org, auth.uid(), 'MODELO_DISPOSITIVO_CREADO', 'MODELO_DISPOSITIVO', v_modelo.id, jsonb_build_object('tipo_dispositivo_id', p_tipo_dispositivo_id, 'marca_dispositivo_id', p_marca_dispositivo_id));
  return v_modelo;
end $$;


ALTER FUNCTION "public"."crear_modelo_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."processor_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_familia_procesador_id" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "activo" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fk_processor_generation_id" "uuid",
    CONSTRAINT "ck_modelos_procesador_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_modelos_procesador_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 120)))
);


ALTER TABLE "public"."processor_models" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_modelo_procesador"("p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_nombre" "text") RETURNS "public"."processor_models"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_modelo public.modelos_procesador;
begin
  if char_length(v_nombre) not between 2 and 120 then raise exception 'INVALID_PROCESSOR'; end if;
  if not exists(select 1 from public.familias_procesador where id=p_familia_procesador_id and fk_marca_procesador_id=p_marca_procesador_id and activo) then raise exception 'INVALID_PROCESSOR_FAMILY'; end if;
  select * into v_modelo from public.modelos_procesador where fk_familia_procesador_id=p_familia_procesador_id and nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_modelo; end if;
  insert into public.modelos_procesador(fk_familia_procesador_id,nombre,alcance,fk_organizacion_id,created_by) values(p_familia_procesador_id,v_nombre,'ORGANIZACION',v_org,auth.uid()) on conflict on constraint uq_modelos_procesador_nombre_alcance do update set updated_at=now() returning * into v_modelo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'MODELO_PROCESADOR_CREADO','MODELO_PROCESADOR',v_modelo.id,jsonb_build_object('familia_procesador_id',p_familia_procesador_id));
  return v_modelo;
end $$;


ALTER FUNCTION "public"."crear_modelo_procesador"("p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_nombre" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."storage_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "activo" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_tipos_almacenamiento_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_tipos_almacenamiento_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 80)))
);


ALTER TABLE "public"."storage_types" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_tipo_almacenamiento"("p_nombre" "text") RETURNS "public"."storage_types"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_nombre text:=regexp_replace(btrim(coalesce(p_nombre,'')),'\s+',' ','g'); v_tipo public.tipos_almacenamiento;
begin
  if char_length(v_nombre) not between 2 and 80 then raise exception 'INVALID_STORAGE_TYPE'; end if;
  select * into v_tipo from public.tipos_almacenamiento where nombre_normalizado=public.normalizar_nombre_catalogo(v_nombre) and activo and (alcance='GLOBAL' or fk_organizacion_id=v_org) order by fk_organizacion_id nulls first limit 1;
  if found then return v_tipo; end if;
  insert into public.tipos_almacenamiento(nombre,alcance,fk_organizacion_id,created_by) values(v_nombre,'ORGANIZACION',v_org,auth.uid()) on conflict on constraint uq_tipos_almacenamiento_nombre_alcance do update set updated_at=now() returning * into v_tipo;
  insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'TIPO_ALMACENAMIENTO_CREADO','TIPO_ALMACENAMIENTO',v_tipo.id,'{}');
  return v_tipo;
end $$;


ALTER FUNCTION "public"."crear_tipo_almacenamiento"("p_nombre" "text") OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."delete_private_device_brand"("p_device_type_id" "uuid", "p_device_brand_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_org uuid := public.assert_reception_owner();
begin
  perform 1
  from public.device_brands b
  join public.device_type_brands r on r.fk_marca_dispositivo_id = b.id
  where b.id = p_device_brand_id
    and r.fk_tipo_dispositivo_id = p_device_type_id
    and b.fk_organizacion_id = v_org
  for update of b;

  if not found then
    raise exception 'DEVICE_BRAND_FORBIDDEN';
  end if;

  if exists (select 1 from public.customer_devices where fk_marca_dispositivo_id = p_device_brand_id)
    or exists (select 1 from public.device_models where fk_marca_dispositivo_id = p_device_brand_id) then
    raise exception 'DEVICE_BRAND_IN_USE';
  end if;

  delete from public.device_type_brands
  where fk_tipo_dispositivo_id = p_device_type_id
    and fk_marca_dispositivo_id = p_device_brand_id;

  delete from public.device_brands
  where id = p_device_brand_id
    and fk_organizacion_id = v_org;
end;
$$;


ALTER FUNCTION "public"."delete_private_device_brand"("p_device_type_id" "uuid", "p_device_brand_id" "uuid") OWNER TO "postgres";


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



CREATE OR REPLACE FUNCTION "public"."get_compatible_processor_brands"("p_device_type_code" "text") RETURNS TABLE("id" "uuid", "name" "text", "parent_id" "uuid", "secondary_parent_id" "uuid", "organization_id" "uuid")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_compatible_processor_brands"("p_device_type_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_compatible_processor_families"("p_device_type_code" "text", "p_brand_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "parent_id" "uuid", "secondary_parent_id" "uuid", "organization_id" "uuid")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select f.id,f.nombre,f.fk_marca_procesador_id,null::uuid,null::uuid
  from public.processor_families f join public.processor_brands b on b.id=f.fk_marca_procesador_id and b.activo
  where f.activo and f.fk_marca_procesador_id=p_brand_id and p_device_type_code in ('desktop_pc','notebook') and exists (
    select 1 from public.processor_models m join public.processor_specifications s on s.fk_processor_model_id=m.id
    where m.fk_familia_procesador_id=f.id and m.activo
      and (m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id())
      and ((p_device_type_code='desktop_pc' and s.desktop_supported) or (p_device_type_code='notebook' and s.notebook_supported))
  ) order by f.nombre_normalizado,f.id;
$$;


ALTER FUNCTION "public"."get_compatible_processor_families"("p_device_type_code" "text", "p_brand_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_compatible_processor_generations"("p_device_type_code" "text", "p_brand_id" "uuid", "p_family_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "parent_id" "uuid", "secondary_parent_id" "uuid", "organization_id" "uuid")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_compatible_processor_generations"("p_device_type_code" "text", "p_brand_id" "uuid", "p_family_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_compatible_processor_models"("p_device_type_code" "text", "p_family_id" "uuid", "p_generation_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "parent_id" "uuid", "secondary_parent_id" "uuid", "organization_id" "uuid")
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
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


ALTER FUNCTION "public"."get_compatible_processor_models"("p_device_type_code" "text", "p_family_id" "uuid", "p_generation_id" "uuid") OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."registrar_foto_recepcion"("p_recepcion_dispositivo_id" "uuid", "p_ruta_storage" "text", "p_descripcion" "text" DEFAULT NULL::"text", "p_clave_control" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_org uuid := public.assert_reception_owner();
  v_id uuid;
begin
  if not exists (
    select 1 from public.recepciones_dispositivos
    where id = p_recepcion_dispositivo_id
      and fk_organizacion_id = v_org
  ) then
    raise exception 'INVALID_RECEPTION';
  end if;

  if p_ruta_storage is null
     or p_ruta_storage !~ ('^' || v_org::text || '/' || p_recepcion_dispositivo_id::text || '/[^/].*$') then
    raise exception 'INVALID_STORAGE_PATH';
  end if;

  if p_clave_control is not null and not exists (
    select 1
    from public.resultados_control_recepcion r
    join public.controles_recepcion_dispositivo c
      on c.id = r.fk_control_recepcion_dispositivo_id
    where r.fk_recepcion_dispositivo_id = p_recepcion_dispositivo_id
      and c.clave = p_clave_control
  ) then
    raise exception 'INVALID_RECEPTION_CONTROL';
  end if;

  insert into public.fotos_recepcion(
    fk_recepcion_dispositivo_id, ruta_storage, descripcion, clave_control, created_by
  ) values (
    p_recepcion_dispositivo_id,
    p_ruta_storage,
    nullif(btrim(p_descripcion), ''),
    nullif(btrim(p_clave_control), ''),
    auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(
    organization_id, actor_user_id, event_type, entity_type, entity_id, metadata
  ) values (
    v_org, auth.uid(), 'FOTO_RECEPCION_REGISTRADA', 'FOTO_RECEPCION', v_id,
    jsonb_build_object('recepcion_dispositivo_id', p_recepcion_dispositivo_id)
  );

  return v_id;
end;
$_$;


ALTER FUNCTION "public"."registrar_foto_recepcion"("p_recepcion_dispositivo_id" "uuid", "p_ruta_storage" "text", "p_descripcion" "text", "p_clave_control" "text") OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."save_customer_device_identification"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text" DEFAULT NULL::"text", "p_observations" "text" DEFAULT NULL::"text", "p_customer_device_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_org uuid:=public.assert_reception_owner(); v_id uuid;
begin
  if not exists(select 1 from public.customers where id=p_customer_id and organization_id=v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  if not exists(select 1 from public.device_types where id=p_device_type_id and is_active) then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if not exists(select 1 from public.device_type_brands r join public.device_brands b on b.id=r.fk_marca_dispositivo_id where r.fk_tipo_dispositivo_id=p_device_type_id and r.fk_marca_dispositivo_id=p_device_brand_id and b.is_active and (b.alcance='GLOBAL' or b.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if not exists(select 1 from public.device_models m where m.id=p_device_model_id and m.fk_tipo_dispositivo_id=p_device_type_id and m.fk_marca_dispositivo_id=p_device_brand_id and m.is_active and (m.alcance='GLOBAL' or m.fk_organizacion_id=v_org)) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if char_length(coalesce(p_serial_number,''))>120 then raise exception 'INVALID_DEVICE_DATA'; end if;
  if p_customer_device_id is null then
    insert into public.customer_devices(fk_organizacion_id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,numero_serie,created_by)
    values(v_org,p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,nullif(btrim(p_serial_number),''),auth.uid()) returning id into v_id;
  else
    update public.customer_devices set fk_tipo_dispositivo_id=p_device_type_id,fk_marca_dispositivo_id=p_device_brand_id,fk_modelo_dispositivo_id=p_device_model_id,numero_serie=nullif(btrim(p_serial_number),''),updated_at=now()
    where id=p_customer_device_id and fk_cliente_id=p_customer_id and fk_organizacion_id=v_org returning id into v_id;
    if v_id is null then raise exception 'INVALID_DEVICE'; end if;
  end if;
  return v_id;
end $$;


ALTER FUNCTION "public"."save_customer_device_identification"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_customer_device_step_two"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text" DEFAULT NULL::"text", "p_observations" "text" DEFAULT NULL::"text", "p_customer_device_id" "uuid" DEFAULT NULL::"uuid", "p_attributes" "jsonb" DEFAULT '{}'::"jsonb", "p_ram_modules" "jsonb" DEFAULT '[]'::"jsonb", "p_storage_drives" "jsonb" DEFAULT '[]'::"jsonb", "p_ports" "jsonb" DEFAULT '[]'::"jsonb", "p_accessory_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_device_id uuid; v_item jsonb;
begin
  perform public.assert_reception_owner();
  if jsonb_typeof(p_attributes)<>'object' or jsonb_typeof(p_ram_modules)<>'array' or jsonb_typeof(p_storage_drives)<>'array' or jsonb_typeof(p_ports)<>'array' then raise exception 'INVALID_DEVICE_DATA'; end if;
  v_device_id:=public.save_customer_device_identification(p_customer_id,p_device_type_id,p_device_brand_id,p_device_model_id,p_serial_number,p_observations,p_customer_device_id);
  delete from public.customer_device_ram_modules where fk_customer_device_id=v_device_id;
  for v_item in select value from jsonb_array_elements(p_ram_modules) loop
    insert into public.customer_device_ram_modules(fk_customer_device_id,fk_ram_type_id,fk_ram_speed_id,capacity_mb,fk_ram_form_factor_id,is_soldered,manufacturer,model)
    values(v_device_id,(v_item->>'type')::uuid,nullif(v_item->>'speedId','')::uuid,(v_item->>'capacity')::integer * 1024,nullif(v_item->>'formFactorId','')::uuid,coalesce((v_item->>'soldered')::boolean,false),nullif(btrim(v_item->>'manufacturer'),''),nullif(btrim(v_item->>'model'),''));
  end loop;
  delete from public.customer_device_ports where fk_customer_device_id=v_device_id;
  for v_item in select value from jsonb_array_elements(p_ports) loop
    insert into public.customer_device_ports(fk_customer_device_id,fk_port_connector_id,fk_port_protocol_id,quantity,condition)
    values(v_device_id,(v_item->>'connectorId')::uuid,nullif(v_item->>'protocolId','')::uuid,(v_item->>'quantity')::integer,nullif(v_item->>'condition',''));
  end loop;
  delete from public.customer_device_storage_drives where fk_customer_device_id=v_device_id;
  for v_item in select value from jsonb_array_elements(p_storage_drives) loop
    insert into public.customer_device_storage_drives(fk_customer_device_id,fk_storage_type_id,fk_storage_interface_id,fk_storage_form_factor_id,fk_storage_capacity_id,capacity_gb,manufacturer,model,serial_number,condition)
    values(v_device_id,nullif(v_item->>'type','')::uuid,nullif(v_item->>'interfaceId','')::uuid,nullif(v_item->>'formFactorId','')::uuid,nullif(v_item->>'capacity','')::uuid,
      (select capacity_gb from public.storage_capacities where id=nullif(v_item->>'capacity','')::uuid),nullif(btrim(v_item->>'manufacturer'),''),nullif(btrim(v_item->>'model'),''),nullif(btrim(v_item->>'serialNumber'),''),nullif(btrim(v_item->>'condition'),''));
  end loop;
  delete from public.customer_device_accessories where fk_dispositivo_cliente_id=v_device_id;
  insert into public.customer_device_accessories(fk_dispositivo_cliente_id,fk_accesorio_dispositivo_id,cantidad)
  select v_device_id,id,1 from unnest(coalesce(p_accessory_ids,'{}'::uuid[])) id;
  delete from public.customer_device_field_values where fk_dispositivo_cliente_id=v_device_id;
  insert into public.customer_device_field_values(fk_dispositivo_cliente_id,fk_tipo_dispositivo_campo_id,valor_texto)
  select v_device_id,b.id,nullif(entry.value,'')
  from jsonb_each_text(p_attributes) entry
  join public.device_fields f on f.key=entry.key and f.is_active
  join public.device_type_fields b on b.fk_campo_dispositivo_id=f.id and b.fk_tipo_dispositivo_id=p_device_type_id and b.is_active
  where entry.value<>'';
  delete from public.customer_device_connectivity where fk_customer_device_id=v_device_id;
  insert into public.customer_device_connectivity(fk_customer_device_id,fk_connectivity_id)
  select v_device_id,value::uuid
  from jsonb_array_elements_text(coalesce(nullif(p_attributes->>'connectivity','')::jsonb,'[]'::jsonb));
  insert into public.customer_device_hardware_profiles(fk_customer_device_id,fk_processor_model_id,gpu_brand_id,gpu_family_id,gpu_model_id,fk_display_size_id,fk_display_resolution_id,fk_display_technology_id,fk_display_refresh_rate_id,display_touch,battery_present,battery_functional_status,charger_delivered,charger_condition,updated_at)
  values(v_device_id,nullif(p_attributes->>'processor_model_id','')::uuid,nullif(p_attributes->>'gpu_brand_id','')::uuid,nullif(p_attributes->>'gpu_family_id','')::uuid,nullif(p_attributes->>'gpu_model_id','')::uuid,
    nullif(p_attributes->>'screen_size','')::uuid,nullif(p_attributes->>'screen_resolution','')::uuid,nullif(p_attributes->>'screen_technology','')::uuid,nullif(p_attributes->>'screen_refresh_rate','')::uuid,coalesce((p_attributes->>'screen_touch')::boolean,false),
    coalesce((p_attributes->>'battery_present')::boolean,false),nullif(p_attributes->>'battery_status',''),coalesce((p_attributes->>'charger_delivered')::boolean,false),nullif(p_attributes->>'charger_status',''),now())
  on conflict(fk_customer_device_id) do update set fk_processor_model_id=excluded.fk_processor_model_id,gpu_brand_id=excluded.gpu_brand_id,gpu_family_id=excluded.gpu_family_id,gpu_model_id=excluded.gpu_model_id,fk_display_size_id=excluded.fk_display_size_id,fk_display_resolution_id=excluded.fk_display_resolution_id,fk_display_technology_id=excluded.fk_display_technology_id,fk_display_refresh_rate_id=excluded.fk_display_refresh_rate_id,display_touch=excluded.display_touch,battery_present=excluded.battery_present,battery_functional_status=excluded.battery_functional_status,charger_delivered=excluded.charger_delivered,charger_condition=excluded.charger_condition,updated_at=now();
  return v_device_id;
end $$;


ALTER FUNCTION "public"."save_customer_device_step_two"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid", "p_attributes" "jsonb", "p_ram_modules" "jsonb", "p_storage_drives" "jsonb", "p_ports" "jsonb", "p_accessory_ids" "uuid"[]) OWNER TO "postgres";


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
    "fk_default_measurement_unit_id" "uuid",
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


CREATE TABLE IF NOT EXISTS "public"."component_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "clave" "text" NOT NULL,
    "nombre" "text" NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_categorias_componente_clave" CHECK (("clave" ~ '^[A-Z][A-Z_]{1,40}$'::"text"))
);


ALTER TABLE "public"."component_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_category_brands" (
    "fk_categoria_componente_id" "uuid" NOT NULL,
    "fk_marca_componente_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."component_category_brands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_specifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_device_component_id" "uuid" NOT NULL,
    "fk_component_attribute_definition_id" "uuid" NOT NULL,
    "text_value" "text",
    "numeric_value" numeric,
    "boolean_value" boolean,
    "fk_measurement_unit_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "component_specifications_check" CHECK (("num_nonnulls"("text_value", "numeric_value", "boolean_value") = 1))
);


ALTER TABLE "public"."component_specifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."component_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "max_instances" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "code" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
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


CREATE TABLE IF NOT EXISTS "public"."customer_device_accessories" (
    "fk_dispositivo_cliente_id" "uuid" NOT NULL,
    "fk_accesorio_dispositivo_id" "uuid" NOT NULL,
    "cantidad" smallint DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_dispositivos_clientes_accesorios_cantidad" CHECK ((("cantidad" >= 1) AND ("cantidad" <= 100)))
);


ALTER TABLE "public"."customer_device_accessories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_checklist_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "item_key" "text" NOT NULL,
    "status" "text" NOT NULL,
    "observation" "text",
    CONSTRAINT "customer_device_checklist_items_item_key_check" CHECK (("item_key" ~ '^[a-z][a-z0-9_]{1,80}$'::"text")),
    CONSTRAINT "customer_device_checklist_items_status_check" CHECK (("status" = ANY (ARRAY['CORRECT'::"text", 'FAULT'::"text", 'NOT_TESTED'::"text", 'NOT_APPLICABLE'::"text"])))
);


ALTER TABLE "public"."customer_device_checklist_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_connectivity" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_connectivity_id" "uuid" NOT NULL,
    "fk_wifi_standard_id" "uuid",
    "condition" "text"
);


ALTER TABLE "public"."customer_device_connectivity" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_field_values" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_dispositivo_cliente_id" "uuid" NOT NULL,
    "fk_tipo_dispositivo_campo_id" "uuid" NOT NULL,
    "valor_texto" "text",
    "valor_numero" numeric,
    "valor_booleano" boolean,
    "valor_json" "jsonb",
    "fk_opcion_campo_dispositivo_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_valores_campos_dispositivo_texto" CHECK ((("valor_texto" IS NULL) OR (("valor_texto" = "btrim"("valor_texto")) AND ("valor_texto" <> ''::"text")))),
    CONSTRAINT "ck_valores_campos_dispositivo_un_valor" CHECK (("num_nonnulls"("valor_texto", "valor_numero", "valor_booleano", "valor_json", "fk_opcion_campo_dispositivo_id") = 1))
);


ALTER TABLE "public"."customer_device_field_values" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_hardware_profiles" (
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_processor_model_id" "uuid",
    "fk_motherboard_brand_id" "uuid",
    "motherboard_model" "text",
    "fk_motherboard_socket_id" "uuid",
    "motherboard_chipset" "text",
    "fk_motherboard_form_factor_id" "uuid",
    "gpu_mode" "text",
    "gpu_vram_mb" integer,
    "psu_manufacturer" "text",
    "psu_model" "text",
    "psu_watts" integer,
    "fk_psu_certification_id" "uuid",
    "fk_display_size_id" "uuid",
    "fk_display_resolution_id" "uuid",
    "fk_display_technology_id" "uuid",
    "fk_display_refresh_rate_id" "uuid",
    "display_touch" boolean,
    "display_condition" "text",
    "battery_present" boolean,
    "battery_design_capacity_wh" numeric(8,2),
    "battery_current_capacity_wh" numeric(8,2),
    "battery_cycles" integer,
    "battery_visual_status" "text",
    "battery_functional_status" "text",
    "charger_delivered" boolean,
    "charger_kind" "text",
    "charger_manufacturer" "text",
    "charger_watts" integer,
    "charger_voltage" numeric(7,2),
    "charger_amperage" numeric(7,2),
    "fk_charger_connector_id" "uuid",
    "charger_condition" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "gpu_brand_id" "uuid",
    "gpu_family_id" "uuid",
    "gpu_model_id" "uuid",
    CONSTRAINT "customer_device_hardware_prof_battery_current_capacity_wh_check" CHECK ((("battery_current_capacity_wh" IS NULL) OR ("battery_current_capacity_wh" >= (0)::numeric))),
    CONSTRAINT "customer_device_hardware_profi_battery_design_capacity_wh_check" CHECK ((("battery_design_capacity_wh" IS NULL) OR ("battery_design_capacity_wh" > (0)::numeric))),
    CONSTRAINT "customer_device_hardware_profiles_battery_cycles_check" CHECK ((("battery_cycles" IS NULL) OR ("battery_cycles" >= 0))),
    CONSTRAINT "customer_device_hardware_profiles_charger_amperage_check" CHECK ((("charger_amperage" IS NULL) OR ("charger_amperage" > (0)::numeric))),
    CONSTRAINT "customer_device_hardware_profiles_charger_kind_check" CHECK (("charger_kind" = ANY (ARRAY['ORIGINAL'::"text", 'ALTERNATIVE'::"text"]))),
    CONSTRAINT "customer_device_hardware_profiles_charger_voltage_check" CHECK ((("charger_voltage" IS NULL) OR ("charger_voltage" > (0)::numeric))),
    CONSTRAINT "customer_device_hardware_profiles_charger_watts_check" CHECK ((("charger_watts" IS NULL) OR ("charger_watts" > 0))),
    CONSTRAINT "customer_device_hardware_profiles_gpu_mode_check" CHECK (("gpu_mode" = ANY (ARRAY['INTEGRATED'::"text", 'DEDICATED'::"text"]))),
    CONSTRAINT "customer_device_hardware_profiles_gpu_vram_mb_check" CHECK ((("gpu_vram_mb" IS NULL) OR ("gpu_vram_mb" > 0))),
    CONSTRAINT "customer_device_hardware_profiles_psu_watts_check" CHECK ((("psu_watts" IS NULL) OR ("psu_watts" > 0)))
);


ALTER TABLE "public"."customer_device_hardware_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_operating_systems" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_operating_system_id" "uuid" NOT NULL,
    "is_primary" boolean DEFAULT false NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."customer_device_operating_systems" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_ports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_port_connector_id" "uuid" NOT NULL,
    "fk_port_protocol_id" "uuid",
    "quantity" smallint DEFAULT 1 NOT NULL,
    "condition" "text",
    CONSTRAINT "customer_device_ports_quantity_check" CHECK (("quantity" > 0))
);


ALTER TABLE "public"."customer_device_ports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_ram_modules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_ram_type_id" "uuid" NOT NULL,
    "fk_ram_speed_id" "uuid",
    "capacity_mb" integer NOT NULL,
    "form_factor" "text",
    "is_soldered" boolean DEFAULT false NOT NULL,
    "manufacturer" "text",
    "model" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fk_ram_form_factor_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_device_ram_modules_capacity_mb_check" CHECK (("capacity_mb" > 0))
);


ALTER TABLE "public"."customer_device_ram_modules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_device_storage_drives" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_storage_type_id" "uuid",
    "fk_storage_interface_id" "uuid",
    "fk_storage_form_factor_id" "uuid",
    "capacity_gb" integer,
    "manufacturer" "text",
    "model" "text",
    "serial_number" "text",
    "condition" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fk_storage_capacity_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "customer_device_storage_drives_capacity_gb_check" CHECK (("capacity_gb" > 0))
);


ALTER TABLE "public"."customer_device_storage_drives" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_organizacion_id" "uuid" NOT NULL,
    "fk_cliente_id" "uuid" NOT NULL,
    "fk_tipo_dispositivo_id" "uuid" NOT NULL,
    "fk_marca_dispositivo_id" "uuid",
    "fk_modelo_dispositivo_id" "uuid",
    "fk_variante_modelo_dispositivo_id" "uuid",
    "fk_color_dispositivo_id" "uuid",
    "numero_serie" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "observations" "text",
    "fk_motherboard_model_id" "uuid",
    CONSTRAINT "ck_dispositivos_clientes_modelo_requiere_marca" CHECK ((("fk_modelo_dispositivo_id" IS NULL) OR ("fk_marca_dispositivo_id" IS NOT NULL))),
    CONSTRAINT "ck_dispositivos_clientes_numero_serie" CHECK ((("numero_serie" IS NULL) OR (("numero_serie" = "btrim"("numero_serie")) AND ("numero_serie" <> ''::"text") AND ("char_length"("numero_serie") <= 120)))),
    CONSTRAINT "ck_dispositivos_clientes_variante_requiere_modelo" CHECK ((("fk_variante_modelo_dispositivo_id" IS NULL) OR ("fk_modelo_dispositivo_id" IS NOT NULL)))
);


ALTER TABLE "public"."customer_devices" OWNER TO "postgres";


COMMENT ON COLUMN "public"."customer_devices"."fk_motherboard_model_id" IS 'Motherboard instalada actualmente; NULL representa desconocida o pendiente de catalogar.';



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



CREATE TABLE IF NOT EXISTS "public"."device_color_families" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_device_color_families_name" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 80)))
);


ALTER TABLE "public"."device_color_families" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_color_family_memberships" (
    "color_id" "uuid" NOT NULL,
    "family_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_color_family_memberships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_components" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_customer_device_id" "uuid" NOT NULL,
    "fk_component_type_id" "uuid" NOT NULL,
    "manufacturer" "text",
    "model" "text",
    "serial_number" "text",
    "notes" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_components_sort_order_check" CHECK (("sort_order" >= 0))
);


ALTER TABLE "public"."device_components" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_diagnostics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_organizacion_id" "uuid" NOT NULL,
    "fk_recepcion_dispositivo_id" "uuid" NOT NULL,
    "diagnostico" "text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_diagnosticos_dispositivo_texto" CHECK ((("char_length"("btrim"("diagnostico")) >= 1) AND ("char_length"("btrim"("diagnostico")) <= 4000)))
);


ALTER TABLE "public"."device_diagnostics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_field_dependencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_tipo_dispositivo_campo_id" "uuid" NOT NULL,
    "fk_tipo_dispositivo_campo_padre_id" "uuid" NOT NULL,
    "operator" "text" NOT NULL,
    "expected_value" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_dependencias_campo_dispositivo_distintas" CHECK (("fk_tipo_dispositivo_campo_id" <> "fk_tipo_dispositivo_campo_padre_id")),
    CONSTRAINT "ck_dependencias_campo_dispositivo_operador" CHECK (("operator" = ANY (ARRAY['EQUALS'::"text", 'NOT_EQUALS'::"text", 'IN'::"text", 'NOT_EMPTY'::"text", 'EMPTY'::"text"])))
);


ALTER TABLE "public"."device_field_dependencies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_field_options" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_campo_dispositivo_id" "uuid" NOT NULL,
    "value" "text" NOT NULL,
    "label" "text" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_opciones_campo_dispositivo_etiqueta" CHECK ((("label" = "btrim"("label")) AND ("label" <> ''::"text") AND ("char_length"("label") <= 160))),
    CONSTRAINT "ck_opciones_campo_dispositivo_valor" CHECK ((("value" = "btrim"("value")) AND ("value" <> ''::"text") AND ("char_length"("value") <= 160)))
);


ALTER TABLE "public"."device_field_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_fields" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "data_source_key" "text",
    "placeholder" "text",
    "help_text" "text",
    "validation" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_campos_dispositivo_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_campos_dispositivo_clave" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "ck_campos_dispositivo_tipo" CHECK (("field_type" = ANY (ARRAY['TEXT'::"text", 'NUMBER'::"text", 'TEXTAREA'::"text", 'SELECT'::"text", 'MULTISELECT'::"text", 'CHECKBOX'::"text", 'RADIO'::"text", 'SWITCH'::"text", 'REPEATABLE'::"text"]))),
    CONSTRAINT "ck_campos_dispositivo_validacion" CHECK (("jsonb_typeof"("validation") = 'object'::"text")),
    CONSTRAINT "device_fields_data_source_key_check" CHECK ((("data_source_key" IS NULL) OR ("data_source_key" = ANY (ARRAY['brand'::"text", 'family'::"text", 'model'::"text", 'variant'::"text", 'color'::"text", 'memory_capacity'::"text", 'storage_capacity'::"text", 'storage_type'::"text", 'operating_system'::"text", 'mobile_operator'::"text", 'accessory'::"text", 'lock_type'::"text", 'notebook_keyboard_mount'::"text", 'hardware_processor_brand'::"text", 'hardware_processor_family'::"text", 'hardware_processor_generation'::"text", 'hardware_processor_model'::"text", 'hardware_motherboard_brand'::"text", 'hardware_motherboard_model'::"text", 'hardware_gpu_brand'::"text", 'hardware_gpu_family'::"text", 'hardware_gpu_model'::"text", 'hardware_power_supply_brand'::"text", 'hardware_power_supply_model'::"text", 'hardware_case_brand'::"text", 'hardware_case_model'::"text", 'hardware_cpu_cooler_brand'::"text", 'hardware_cpu_cooler_model'::"text", 'hardware_wifi_brand'::"text", 'hardware_wifi_model'::"text", 'device_brand'::"text", 'device_model'::"text", 'ram_modules'::"text", 'storage_drives'::"text", 'hardware_display_size'::"text", 'hardware_display_resolution'::"text", 'hardware_display_technology'::"text", 'hardware_display_refresh_rate'::"text", 'hardware_connectivity'::"text", 'hardware_port'::"text"]))))
);


ALTER TABLE "public"."device_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_form_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "alcance" "text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "ui_config" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    CONSTRAINT "ck_secciones_formulario_dispositivo_alcance" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL)))),
    CONSTRAINT "ck_secciones_formulario_dispositivo_clave" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "device_form_sections_ui_config_check" CHECK (("jsonb_typeof"("ui_config") = 'object'::"text")),
    CONSTRAINT "device_form_sections_ui_config_object" CHECK (("jsonb_typeof"("ui_config") = 'object'::"text"))
);


ALTER TABLE "public"."device_form_sections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_model_variants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_modelo_dispositivo_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_variantes_modelo_dispositivo_nombre" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 140)))
);


ALTER TABLE "public"."device_model_variants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_reception_controls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "descripcion" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_critical" boolean DEFAULT false NOT NULL,
    CONSTRAINT "ck_controles_recepcion_dispositivo_clave" CHECK (("key" ~ '^[a-z][a-z0-9_]{1,60}$'::"text")),
    CONSTRAINT "ck_controles_recepcion_dispositivo_etiqueta" CHECK ((("char_length"("btrim"("label")) >= 2) AND ("char_length"("btrim"("label")) <= 120)))
);


ALTER TABLE "public"."device_reception_controls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_receptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_organizacion_id" "uuid" NOT NULL,
    "fk_dispositivo_cliente_id" "uuid" NOT NULL,
    "reported_problem" "text" NOT NULL,
    "observations" "text",
    "condition_score" numeric(6,1) NOT NULL,
    "calculated_condition" "text" NOT NULL,
    "snapshot_ingreso" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'CONFIRMADA'::"text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_recepciones_dispositivos_estado" CHECK (("status" = 'CONFIRMADA'::"text")),
    CONSTRAINT "ck_recepciones_dispositivos_observaciones" CHECK ((("observations" IS NULL) OR (("observations" = "btrim"("observations")) AND ("char_length"("observations") <= 2000)))),
    CONSTRAINT "ck_recepciones_dispositivos_problema" CHECK ((("char_length"("btrim"("reported_problem")) >= 10) AND ("char_length"("btrim"("reported_problem")) <= 2000))),
    CONSTRAINT "ck_recepciones_dispositivos_puntaje" CHECK (("condition_score" >= (0)::numeric)),
    CONSTRAINT "ck_recepciones_dispositivos_snapshot" CHECK (("jsonb_typeof"("snapshot_ingreso") = 'object'::"text"))
);


ALTER TABLE "public"."device_receptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_brands" (
    "fk_tipo_dispositivo_id" "uuid" NOT NULL,
    "fk_marca_dispositivo_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."device_type_brands" OWNER TO "postgres";


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
    "fk_tipo_dispositivo_id" "uuid" NOT NULL,
    "fk_seccion_formulario_dispositivo_id" "uuid" NOT NULL,
    "fk_campo_dispositivo_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "required" boolean DEFAULT false NOT NULL,
    "overrides" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_tipos_dispositivo_campos_overrides" CHECK (("jsonb_typeof"("overrides") = 'object'::"text"))
);


ALTER TABLE "public"."device_type_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_reception_controls" (
    "fk_tipo_dispositivo_id" "uuid" NOT NULL,
    "fk_control_recepcion_dispositivo_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "obligatorio" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."device_type_reception_controls" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_type_services" (
    "device_type_id" "uuid" NOT NULL,
    "technical_service_id" "uuid" NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."device_type_services" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."device_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "code" "text" NOT NULL,
    "description" "text",
    CONSTRAINT "ck_device_types_code" CHECK (("code" ~ '^[a-z][a-z0-9_]{1,62}$'::"text")),
    CONSTRAINT "ck_tipos_dispositivo_nombre" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 80)))
);


ALTER TABLE "public"."device_types" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."gpu_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."gpu_brands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gpu_families" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_gpu_brand_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."gpu_families" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gpu_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_gpu_family_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "graphics_kind" "text" NOT NULL,
    "desktop_supported" boolean DEFAULT false NOT NULL,
    "notebook_supported" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "gpu_models_graphics_kind_check" CHECK (("graphics_kind" = ANY (ARRAY['INTEGRATED'::"text", 'DEDICATED'::"text"])))
);


ALTER TABLE "public"."gpu_models" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hardware_catalog_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category" "text" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "parent_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "hardware_catalog_items_category_check" CHECK (("category" = ANY (ARRAY['MOTHERBOARD_BRAND'::"text", 'MOTHERBOARD_SOCKET'::"text", 'MOTHERBOARD_FORM_FACTOR'::"text", 'MOTHERBOARD_CHIPSET'::"text", 'PSU_BRAND'::"text", 'PSU_CERTIFICATION'::"text", 'DISPLAY_SIZE'::"text", 'DISPLAY_RESOLUTION'::"text", 'DISPLAY_TECHNOLOGY'::"text", 'DISPLAY_REFRESH_RATE'::"text", 'CHARGER_CONNECTOR'::"text", 'OPERATING_SYSTEM'::"text", 'PORT_CONNECTOR'::"text", 'PORT_PROTOCOL'::"text", 'WIFI_STANDARD'::"text", 'CONNECTIVITY'::"text", 'CHECKLIST_STATUS'::"text"])))
);


ALTER TABLE "public"."hardware_catalog_items" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."measurement_units" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "symbol" "text" NOT NULL,
    "quantity_kind" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "measurement_units_quantity_kind_check" CHECK (("quantity_kind" = ANY (ARRAY['DATA'::"text", 'FREQUENCY'::"text", 'TRANSFER_RATE'::"text", 'POWER'::"text", 'ENERGY'::"text", 'VOLTAGE'::"text", 'LENGTH'::"text"])))
);


ALTER TABLE "public"."measurement_units" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."motherboard_manufacturers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "alcance" "text" DEFAULT 'GLOBAL'::"text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_motherboard_manufacturers_name" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 120))),
    CONSTRAINT "ck_motherboard_manufacturers_scope" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL))))
);


ALTER TABLE "public"."motherboard_manufacturers" OWNER TO "postgres";


COMMENT ON TABLE "public"."motherboard_manufacturers" IS 'Catálogo híbrido de fabricantes de placas madre; los datos iniciales son GLOBAL.';



CREATE TABLE IF NOT EXISTS "public"."motherboard_model_device_types" (
    "motherboard_model_id" "uuid" NOT NULL,
    "device_type_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."motherboard_model_device_types" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."motherboard_models" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "motherboard_manufacturer_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "normalized_name" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("name")) STORED,
    "alcance" "text" DEFAULT 'GLOBAL'::"text" NOT NULL,
    "fk_organizacion_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_motherboard_models_name" CHECK ((("char_length"("btrim"("name")) >= 2) AND ("char_length"("btrim"("name")) <= 200))),
    CONSTRAINT "ck_motherboard_models_scope" CHECK (((("alcance" = 'GLOBAL'::"text") AND ("fk_organizacion_id" IS NULL)) OR (("alcance" = 'ORGANIZACION'::"text") AND ("fk_organizacion_id" IS NOT NULL))))
);


ALTER TABLE "public"."motherboard_models" OWNER TO "postgres";


COMMENT ON TABLE "public"."motherboard_models" IS 'Catálogo híbrido de modelos comerciales de placas madre; conserva nombres como Logic Board.';



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



CREATE TABLE IF NOT EXISTS "public"."operating_systems" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "organization_id" "uuid",
    "name" "text" NOT NULL,
    "platform" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "code" "text",
    "version" "text"
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



CREATE TABLE IF NOT EXISTS "public"."processor_brands" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "activo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_marcas_procesador_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 80)))
);


ALTER TABLE "public"."processor_brands" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."processor_families" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_marca_procesador_id" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "nombre_normalizado" "text" GENERATED ALWAYS AS ("public"."normalizar_nombre_catalogo"("nombre")) STORED,
    "activo" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_familias_procesador_nombre" CHECK ((("char_length"("btrim"("nombre")) >= 2) AND ("char_length"("btrim"("nombre")) <= 80)))
);


ALTER TABLE "public"."processor_families" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."processor_generations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_processor_family_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "sort_order" smallint NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "processor_generations_code_check" CHECK (("code" ~ '^[a-z0-9_]+$'::"text")),
    CONSTRAINT "processor_generations_name_check" CHECK ((("char_length"("btrim"("name")) >= 1) AND ("char_length"("btrim"("name")) <= 80))),
    CONSTRAINT "processor_generations_sort_order_check" CHECK (("sort_order" > 0))
);


ALTER TABLE "public"."processor_generations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."processor_specifications" (
    "fk_processor_model_id" "uuid" NOT NULL,
    "socket" "text",
    "core_count" smallint,
    "thread_count" smallint,
    "base_clock_mhz" integer,
    "integrated_gpu" "text",
    "desktop_supported" boolean DEFAULT true NOT NULL,
    "notebook_supported" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "processor_specifications_base_clock_mhz_check" CHECK ((("base_clock_mhz" IS NULL) OR ("base_clock_mhz" > 0))),
    CONSTRAINT "processor_specifications_check" CHECK (("desktop_supported" OR "notebook_supported")),
    CONSTRAINT "processor_specifications_core_count_check" CHECK ((("core_count" IS NULL) OR ("core_count" > 0))),
    CONSTRAINT "processor_specifications_thread_count_check" CHECK ((("thread_count" IS NULL) OR ("thread_count" > 0)))
);


ALTER TABLE "public"."processor_specifications" OWNER TO "postgres";


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


CREATE TABLE IF NOT EXISTS "public"."ram_form_factors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."ram_form_factors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ram_speeds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_ram_type_id" "uuid" NOT NULL,
    "mhz" integer NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "ram_speeds_mhz_check" CHECK ((("mhz" >= 100) AND ("mhz" <= 20000)))
);


ALTER TABLE "public"."ram_speeds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ram_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."ram_types" OWNER TO "postgres";


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
    "fk_recepcion_dispositivo_id" "uuid" NOT NULL,
    "fk_control_recepcion_dispositivo_id" "uuid" NOT NULL,
    "condition" "text" NOT NULL,
    "severidad" "text",
    "observation" "text",
    "is_critical" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_resultados_control_recepcion_condicion" CHECK (("condition" = ANY (ARRAY['FUNCIONA'::"text", 'FUNCIONA_PARCIALMENTE'::"text", 'NO_FUNCIONA'::"text", 'NO_COMPROBABLE'::"text", 'BUENO'::"text", 'REGULAR'::"text", 'MALO'::"text"]))),
    CONSTRAINT "ck_resultados_control_recepcion_observacion" CHECK ((("observation" IS NULL) OR (("observation" = "btrim"("observation")) AND ("char_length"("observation") <= 2000))))
);


ALTER TABLE "public"."reception_inspection_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reception_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fk_recepcion_dispositivo_id" "uuid" NOT NULL,
    "storage_path" "text" NOT NULL,
    "description" "text",
    "inspection_key" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_fotos_recepcion_descripcion" CHECK ((("description" IS NULL) OR (("description" = "btrim"("description")) AND ("char_length"("description") <= 300)))),
    CONSTRAINT "ck_fotos_recepcion_ruta" CHECK (("storage_path" ~ '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}/[^/].*$'::"text"))
);


ALTER TABLE "public"."reception_photos" OWNER TO "postgres";


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
    "capacity_gb" integer NOT NULL,
    "label" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    CONSTRAINT "storage_capacities_capacity_gb_check" CHECK (("capacity_gb" > 0))
);


ALTER TABLE "public"."storage_capacities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."storage_form_factors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."storage_form_factors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."storage_interfaces" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."storage_interfaces" OWNER TO "postgres";


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



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "accesorios_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."account_deletion_requests"
    ADD CONSTRAINT "account_deletion_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."audit_events"
    ADD CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_rate_limits"
    ADD CONSTRAINT "auth_rate_limits_pkey" PRIMARY KEY ("action", "key_hash");



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "campos_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_category_brands"
    ADD CONSTRAINT "categorias_componente_marcas_pkey" PRIMARY KEY ("fk_categoria_componente_id", "fk_marca_componente_id");



ALTER TABLE ONLY "public"."component_categories"
    ADD CONSTRAINT "categorias_componente_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "colores_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_component_type_id_key_key" UNIQUE ("component_type_id", "key");



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_attribute_definition_id_value_key" UNIQUE ("attribute_definition_id", "value");



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_specifications"
    ADD CONSTRAINT "component_specifications_fk_device_component_id_fk_componen_key" UNIQUE ("fk_device_component_id", "fk_component_attribute_definition_id");



ALTER TABLE ONLY "public"."component_specifications"
    ADD CONSTRAINT "component_specifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "controles_recepcion_dispositivo_clave_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."device_reception_controls"
    ADD CONSTRAINT "controles_recepcion_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."countries"
    ADD CONSTRAINT "countries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_checklist_items"
    ADD CONSTRAINT "customer_device_checklist_ite_fk_customer_device_id_item_ke_key" UNIQUE ("fk_customer_device_id", "item_key");



ALTER TABLE ONLY "public"."customer_device_checklist_items"
    ADD CONSTRAINT "customer_device_checklist_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_connectivity"
    ADD CONSTRAINT "customer_device_connectivity_fk_customer_device_id_fk_conne_key" UNIQUE ("fk_customer_device_id", "fk_connectivity_id", "fk_wifi_standard_id");



ALTER TABLE ONLY "public"."customer_device_connectivity"
    ADD CONSTRAINT "customer_device_connectivity_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_pkey" PRIMARY KEY ("fk_customer_device_id");



ALTER TABLE ONLY "public"."customer_device_operating_systems"
    ADD CONSTRAINT "customer_device_operating_sys_fk_customer_device_id_fk_oper_key" UNIQUE ("fk_customer_device_id", "fk_operating_system_id");



ALTER TABLE ONLY "public"."customer_device_operating_systems"
    ADD CONSTRAINT "customer_device_operating_systems_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_ports"
    ADD CONSTRAINT "customer_device_ports_fk_customer_device_id_fk_port_connect_key" UNIQUE ("fk_customer_device_id", "fk_port_connector_id", "fk_port_protocol_id");



ALTER TABLE ONLY "public"."customer_device_ports"
    ADD CONSTRAINT "customer_device_ports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_ram_modules"
    ADD CONSTRAINT "customer_device_ram_modules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_storage_drives"
    ADD CONSTRAINT "customer_device_storage_drives_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_customer_id_auth_user_id_key" UNIQUE ("customer_id", "auth_user_id");



ALTER TABLE ONLY "public"."customer_user_links"
    ADD CONSTRAINT "customer_user_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "dependencias_campo_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_color_families"
    ADD CONSTRAINT "device_color_families_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_color_family_memberships"
    ADD CONSTRAINT "device_color_family_memberships_pkey" PRIMARY KEY ("color_id", "family_id");



ALTER TABLE ONLY "public"."device_components"
    ADD CONSTRAINT "device_components_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_device_type_id_diagnostic_test_key" UNIQUE ("device_type_id", "diagnostic_test_type_id");



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_pkey" PRIMARY KEY ("device_type_id", "technical_service_id");



ALTER TABLE ONLY "public"."diagnostic_result_types"
    ADD CONSTRAINT "diagnostic_result_types_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."diagnostic_result_types"
    ADD CONSTRAINT "diagnostic_result_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_diagnostics"
    ADD CONSTRAINT "diagnosticos_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_device_accessories"
    ADD CONSTRAINT "dispositivos_clientes_accesorios_pkey" PRIMARY KEY ("fk_dispositivo_cliente_id", "fk_accesorio_dispositivo_id");



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "dispositivos_clientes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."processor_families"
    ADD CONSTRAINT "familias_procesador_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "fotos_recepcion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gpu_brands"
    ADD CONSTRAINT "gpu_brands_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."gpu_brands"
    ADD CONSTRAINT "gpu_brands_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."gpu_brands"
    ADD CONSTRAINT "gpu_brands_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gpu_families"
    ADD CONSTRAINT "gpu_families_fk_gpu_brand_id_code_key" UNIQUE ("fk_gpu_brand_id", "code");



ALTER TABLE ONLY "public"."gpu_families"
    ADD CONSTRAINT "gpu_families_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gpu_models"
    ADD CONSTRAINT "gpu_models_fk_gpu_family_id_code_key" UNIQUE ("fk_gpu_family_id", "code");



ALTER TABLE ONLY "public"."gpu_models"
    ADD CONSTRAINT "gpu_models_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hardware_catalog_items"
    ADD CONSTRAINT "hardware_catalog_items_category_code_key" UNIQUE ("category", "code");



ALTER TABLE ONLY "public"."hardware_catalog_items"
    ADD CONSTRAINT "hardware_catalog_items_pkey" PRIMARY KEY ("id");



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



ALTER TABLE ONLY "public"."component_brands"
    ADD CONSTRAINT "marcas_componente_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "marcas_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."processor_brands"
    ADD CONSTRAINT "marcas_procesador_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."measurement_units"
    ADD CONSTRAINT "measurement_units_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."measurement_units"
    ADD CONSTRAINT "measurement_units_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."component_models"
    ADD CONSTRAINT "modelos_componente_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "modelos_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "modelos_procesador_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."motherboard_manufacturers"
    ADD CONSTRAINT "motherboard_manufacturers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."motherboard_model_device_types"
    ADD CONSTRAINT "motherboard_model_device_types_pkey" PRIMARY KEY ("motherboard_model_id", "device_type_id");



ALTER TABLE ONLY "public"."motherboard_models"
    ADD CONSTRAINT "motherboard_models_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_id_locality_id_key" UNIQUE ("id", "locality_id");



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "opciones_campo_dispositivo_pkey" PRIMARY KEY ("id");



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



ALTER TABLE ONLY "public"."processor_generations"
    ADD CONSTRAINT "processor_generations_fk_processor_family_id_code_key" UNIQUE ("fk_processor_family_id", "code");



ALTER TABLE ONLY "public"."processor_generations"
    ADD CONSTRAINT "processor_generations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."processor_specifications"
    ADD CONSTRAINT "processor_specifications_pkey" PRIMARY KEY ("fk_processor_model_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_id_country_id_key" UNIQUE ("id", "country_id");



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ram_form_factors"
    ADD CONSTRAINT "ram_form_factors_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."ram_form_factors"
    ADD CONSTRAINT "ram_form_factors_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."ram_form_factors"
    ADD CONSTRAINT "ram_form_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ram_speeds"
    ADD CONSTRAINT "ram_speeds_fk_ram_type_id_mhz_key" UNIQUE ("fk_ram_type_id", "mhz");



ALTER TABLE ONLY "public"."ram_speeds"
    ADD CONSTRAINT "ram_speeds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ram_types"
    ADD CONSTRAINT "ram_types_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."ram_types"
    ADD CONSTRAINT "ram_types_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."ram_types"
    ADD CONSTRAINT "ram_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "recepciones_dispositivos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "resultados_control_recepcion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "secciones_formulario_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_capacity_gb_key" UNIQUE ("capacity_gb");



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_label_key" UNIQUE ("label");



ALTER TABLE ONLY "public"."storage_capacities"
    ADD CONSTRAINT "storage_capacities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."storage_form_factors"
    ADD CONSTRAINT "storage_form_factors_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."storage_form_factors"
    ADD CONSTRAINT "storage_form_factors_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."storage_form_factors"
    ADD CONSTRAINT "storage_form_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."storage_interfaces"
    ADD CONSTRAINT "storage_interfaces_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."storage_interfaces"
    ADD CONSTRAINT "storage_interfaces_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."storage_interfaces"
    ADD CONSTRAINT "storage_interfaces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_id_organization_id_key" UNIQUE ("id", "organization_id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."technical_services"
    ADD CONSTRAINT "technical_services_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."storage_types"
    ADD CONSTRAINT "tipos_almacenamiento_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "tipos_dispositivo_campos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "tipos_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "uq_accesorios_dispositivo_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("nombre_normalizado", "fk_organizacion_id");



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "uq_campos_dispositivo_clave_alcance" UNIQUE NULLS NOT DISTINCT ("key", "fk_organizacion_id");



ALTER TABLE ONLY "public"."component_categories"
    ADD CONSTRAINT "uq_categorias_componente_clave" UNIQUE ("clave");



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "uq_colores_dispositivo_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("normalized_name", "fk_organizacion_id");



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "uq_dependencias_campo_dispositivo" UNIQUE ("fk_tipo_dispositivo_campo_id", "fk_tipo_dispositivo_campo_padre_id", "operator");



ALTER TABLE ONLY "public"."device_color_families"
    ADD CONSTRAINT "uq_device_color_families_normalized_name" UNIQUE ("normalized_name");



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "uq_device_types_code" UNIQUE ("code");



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "uq_dispositivos_clientes_id_organizacion" UNIQUE ("id", "fk_organizacion_id");



ALTER TABLE ONLY "public"."processor_families"
    ADD CONSTRAINT "uq_familias_procesador_integridad" UNIQUE ("id", "fk_marca_procesador_id");



ALTER TABLE ONLY "public"."processor_families"
    ADD CONSTRAINT "uq_familias_procesador_nombre" UNIQUE ("fk_marca_procesador_id", "nombre_normalizado");



ALTER TABLE ONLY "public"."component_brands"
    ADD CONSTRAINT "uq_marcas_componente_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("nombre_normalizado", "fk_organizacion_id");



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "uq_marcas_dispositivo_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("normalized_name", "fk_organizacion_id");



ALTER TABLE ONLY "public"."processor_brands"
    ADD CONSTRAINT "uq_marcas_procesador_nombre_normalizado" UNIQUE ("nombre_normalizado");



ALTER TABLE ONLY "public"."component_models"
    ADD CONSTRAINT "uq_modelos_componente_integridad" UNIQUE ("id", "fk_categoria_componente_id", "fk_marca_componente_id");



ALTER TABLE ONLY "public"."component_models"
    ADD CONSTRAINT "uq_modelos_componente_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("fk_categoria_componente_id", "fk_marca_componente_id", "nombre_normalizado", "fk_organizacion_id");



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "uq_modelos_dispositivo_integridad" UNIQUE ("id", "fk_tipo_dispositivo_id", "fk_marca_dispositivo_id");



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "uq_modelos_dispositivo_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("fk_tipo_dispositivo_id", "fk_marca_dispositivo_id", "normalized_name", "fk_organizacion_id");



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "uq_modelos_procesador_integridad" UNIQUE ("id", "fk_familia_procesador_id");



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "uq_modelos_procesador_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("fk_familia_procesador_id", "nombre_normalizado", "fk_organizacion_id");



ALTER TABLE ONLY "public"."motherboard_manufacturers"
    ADD CONSTRAINT "uq_motherboard_manufacturers_name_scope" UNIQUE NULLS NOT DISTINCT ("normalized_name", "fk_organizacion_id");



ALTER TABLE ONLY "public"."motherboard_models"
    ADD CONSTRAINT "uq_motherboard_models_id_manufacturer" UNIQUE ("id", "motherboard_manufacturer_id");



ALTER TABLE ONLY "public"."motherboard_models"
    ADD CONSTRAINT "uq_motherboard_models_name_scope" UNIQUE NULLS NOT DISTINCT ("motherboard_manufacturer_id", "normalized_name", "fk_organizacion_id");



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "uq_opciones_campo_dispositivo_valor" UNIQUE ("fk_campo_dispositivo_id", "value");



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "uq_resultados_control_recepcion" UNIQUE ("fk_recepcion_dispositivo_id", "fk_control_recepcion_dispositivo_id");



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "uq_secciones_formulario_dispositivo_clave_alcance" UNIQUE NULLS NOT DISTINCT ("key", "fk_organizacion_id");



ALTER TABLE ONLY "public"."storage_types"
    ADD CONSTRAINT "uq_tipos_almacenamiento_nombre_alcance" UNIQUE NULLS NOT DISTINCT ("nombre_normalizado", "fk_organizacion_id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "uq_tipos_dispositivo_campos" UNIQUE ("fk_tipo_dispositivo_id", "fk_campo_dispositivo_id");



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "uq_tipos_dispositivo_campos_orden" UNIQUE ("fk_tipo_dispositivo_id", "fk_seccion_formulario_dispositivo_id", "sort_order");



ALTER TABLE ONLY "public"."device_type_reception_controls"
    ADD CONSTRAINT "uq_tipos_dispositivo_controles_recepcion" PRIMARY KEY ("fk_tipo_dispositivo_id", "fk_control_recepcion_dispositivo_id");



ALTER TABLE ONLY "public"."device_type_brands"
    ADD CONSTRAINT "uq_tipos_dispositivo_marcas" PRIMARY KEY ("fk_tipo_dispositivo_id", "fk_marca_dispositivo_id");



ALTER TABLE ONLY "public"."device_types"
    ADD CONSTRAINT "uq_tipos_dispositivo_nombre_normalizado" UNIQUE ("normalized_name");



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "uq_valores_campos_dispositivo_campo" UNIQUE ("fk_dispositivo_cliente_id", "fk_tipo_dispositivo_campo_id");



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "uq_variantes_modelo_dispositivo_integridad" UNIQUE ("id", "fk_modelo_dispositivo_id");



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "uq_variantes_modelo_dispositivo_nombre" UNIQUE ("fk_modelo_dispositivo_id", "normalized_name");



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_user_id_service_key" UNIQUE ("user_id", "service");



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "valores_campos_dispositivo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "variantes_modelo_dispositivo_pkey" PRIMARY KEY ("id");



CREATE INDEX "account_deletion_due_idx" ON "public"."account_deletion_requests" USING "btree" ("scheduled_for") WHERE ("status" = 'PENDING'::"text");



CREATE UNIQUE INDEX "account_deletion_pending_organization_unique" ON "public"."account_deletion_requests" USING "btree" ("organization_id") WHERE (("subject_type" = 'ORGANIZATION'::"text") AND ("status" = 'PENDING'::"text"));



CREATE UNIQUE INDEX "account_deletion_pending_user_unique" ON "public"."account_deletion_requests" USING "btree" ("target_user_id") WHERE (("subject_type" = 'CUSTOMER_ACCOUNT'::"text") AND ("status" = 'PENDING'::"text"));



CREATE INDEX "audit_events_actor_created_idx" ON "public"."audit_events" USING "btree" ("actor_user_id", "created_at" DESC);



CREATE INDEX "audit_events_created_idx" ON "public"."audit_events" USING "btree" ("created_at" DESC);



CREATE INDEX "audit_events_organization_created_idx" ON "public"."audit_events" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "audit_events_result_created_idx" ON "public"."audit_events" USING "btree" ("result", "created_at" DESC);



CREATE INDEX "audit_events_type_created_idx" ON "public"."audit_events" USING "btree" ("event_type", "created_at" DESC);



CREATE INDEX "auth_rate_limits_updated_idx" ON "public"."auth_rate_limits" USING "btree" ("updated_at");



CREATE UNIQUE INDEX "component_types_code_unique" ON "public"."component_types" USING "btree" ("code") WHERE ("code" IS NOT NULL);



CREATE UNIQUE INDEX "component_types_global_unique" ON "public"."component_types" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "component_types_org_unique" ON "public"."component_types" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE UNIQUE INDEX "countries_normalized_name_key" ON "public"."countries" USING "btree" ("normalized_name");



CREATE UNIQUE INDEX "customer_device_one_primary_os_idx" ON "public"."customer_device_operating_systems" USING "btree" ("fk_customer_device_id") WHERE "is_primary";



CREATE INDEX "customer_user_links_organization_idx" ON "public"."customer_user_links" USING "btree" ("organization_id");



CREATE INDEX "customer_user_links_user_idx" ON "public"."customer_user_links" USING "btree" ("auth_user_id");



CREATE UNIQUE INDEX "customers_organization_email_unique" ON "public"."customers" USING "btree" ("organization_id", "lower"("contact_email")) WHERE (("contact_email" IS NOT NULL) AND ("contact_email" <> ''::"text"));



CREATE INDEX "customers_organization_idx" ON "public"."customers" USING "btree" ("organization_id");



CREATE UNIQUE INDEX "customers_organization_phone_unique" ON "public"."customers" USING "btree" ("organization_id", "phone") WHERE (("phone" IS NOT NULL) AND ("phone" <> ''::"text"));



CREATE INDEX "device_components_device_idx" ON "public"."device_components" USING "btree" ("fk_customer_device_id", "fk_component_type_id", "sort_order");



CREATE INDEX "device_type_diagnostic_tests_type_idx" ON "public"."device_type_diagnostic_tests" USING "btree" ("device_type_id", "sort_order") WHERE "is_active";



CREATE UNIQUE INDEX "diagnostic_test_types_global_key_unique" ON "public"."diagnostic_test_types" USING "btree" ("key") WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "diagnostic_test_types_org_key_unique" ON "public"."diagnostic_test_types" USING "btree" ("organization_id", "key") WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "gpu_families_brand_idx" ON "public"."gpu_families" USING "btree" ("fk_gpu_brand_id");



CREATE INDEX "gpu_models_family_idx" ON "public"."gpu_models" USING "btree" ("fk_gpu_family_id");



CREATE INDEX "inventory_brands_organization_active_idx" ON "public"."inventory_brands" USING "btree" ("organization_id", "is_active", "name");



CREATE INDEX "inventory_categories_active_name_idx" ON "public"."inventory_categories" USING "btree" ("is_active", "name");



CREATE INDEX "inventory_items_organization_active_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "is_active", "normalized_name");



CREATE INDEX "inventory_items_organization_brand_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "brand_id") WHERE ("brand_id" IS NOT NULL);



CREATE INDEX "inventory_items_organization_category_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "category_id");



CREATE UNIQUE INDEX "inventory_items_organization_sku_key" ON "public"."inventory_items" USING "btree" ("organization_id", "normalized_sku") WHERE ("normalized_sku" IS NOT NULL);



CREATE INDEX "inventory_items_organization_supplier_idx" ON "public"."inventory_items" USING "btree" ("organization_id", "preferred_supplier_id") WHERE ("preferred_supplier_id" IS NOT NULL);



CREATE INDEX "inventory_movements_item_created_idx" ON "public"."inventory_movements" USING "btree" ("inventory_item_id", "created_at" DESC);



CREATE INDEX "inventory_movements_organization_created_idx" ON "public"."inventory_movements" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "ix_categorias_componente_marcas_marca" ON "public"."component_category_brands" USING "btree" ("fk_marca_componente_id", "fk_categoria_componente_id");



CREATE INDEX "ix_customer_device_ram_modules_device" ON "public"."customer_device_ram_modules" USING "btree" ("fk_customer_device_id");



CREATE INDEX "ix_customer_device_storage_drives_device" ON "public"."customer_device_storage_drives" USING "btree" ("fk_customer_device_id");



CREATE INDEX "ix_customer_devices_motherboard_model" ON "public"."customer_devices" USING "btree" ("fk_motherboard_model_id") WHERE ("fk_motherboard_model_id" IS NOT NULL);



CREATE INDEX "ix_device_color_family_memberships_family_id" ON "public"."device_color_family_memberships" USING "btree" ("family_id");



CREATE INDEX "ix_dispositivos_clientes_marca_dispositivo" ON "public"."customer_devices" USING "btree" ("fk_marca_dispositivo_id");



CREATE INDEX "ix_dispositivos_clientes_organizacion_cliente" ON "public"."customer_devices" USING "btree" ("fk_organizacion_id", "fk_cliente_id");



CREATE INDEX "ix_familias_procesador_marca" ON "public"."processor_families" USING "btree" ("fk_marca_procesador_id", "nombre_normalizado");



CREATE INDEX "ix_hardware_catalog_items_category" ON "public"."hardware_catalog_items" USING "btree" ("category", "parent_id") WHERE "is_active";



CREATE INDEX "ix_modelos_componente_catalogo" ON "public"."component_models" USING "btree" ("fk_categoria_componente_id", "fk_marca_componente_id", "nombre_normalizado");



CREATE INDEX "ix_modelos_procesador_familia" ON "public"."processor_models" USING "btree" ("fk_familia_procesador_id", "nombre_normalizado");



CREATE INDEX "ix_motherboard_model_device_types_device_type" ON "public"."motherboard_model_device_types" USING "btree" ("device_type_id", "motherboard_model_id");



CREATE INDEX "ix_processor_generations_family" ON "public"."processor_generations" USING "btree" ("fk_processor_family_id", "sort_order") WHERE "is_active";



CREATE INDEX "ix_processor_models_generation" ON "public"."processor_models" USING "btree" ("fk_processor_generation_id") WHERE "activo";



CREATE INDEX "ix_recepciones_dispositivos_organizacion_creada" ON "public"."device_receptions" USING "btree" ("fk_organizacion_id", "created_at" DESC);



CREATE INDEX "localities_province_idx" ON "public"."localities" USING "btree" ("province_id", "name");



CREATE UNIQUE INDEX "localities_province_normalized_name_key" ON "public"."localities" USING "btree" ("province_id", "normalized_name");



CREATE INDEX "neighborhoods_locality_idx" ON "public"."neighborhoods" USING "btree" ("locality_id", "name");



CREATE UNIQUE INDEX "neighborhoods_locality_normalized_name_key" ON "public"."neighborhoods" USING "btree" ("locality_id", "normalized_name");



CREATE UNIQUE INDEX "operating_systems_code_unique" ON "public"."operating_systems" USING "btree" ("code") WHERE ("code" IS NOT NULL);



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



CREATE UNIQUE INDEX "service_categories_global_unique" ON "public"."service_categories" USING "btree" ("lower"("name")) WHERE ("organization_id" IS NULL);



CREATE UNIQUE INDEX "service_categories_org_unique" ON "public"."service_categories" USING "btree" ("organization_id", "lower"("name")) WHERE ("organization_id" IS NOT NULL);



CREATE INDEX "suppliers_organization_active_idx" ON "public"."suppliers" USING "btree" ("organization_id", "is_active", "normalized_name");



CREATE INDEX "technical_services_category_idx" ON "public"."technical_services" USING "btree" ("service_category_id", "name") WHERE "is_active";



CREATE UNIQUE INDEX "uq_customer_devices_organization_serial_number" ON "public"."customer_devices" USING "btree" ("fk_organizacion_id", "lower"("numero_serie")) WHERE ("numero_serie" IS NOT NULL);



CREATE INDEX "user_quick_links_user_enabled_idx" ON "public"."user_quick_links" USING "btree" ("user_id", "enabled");



CREATE OR REPLACE TRIGGER "customers_set_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



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



CREATE OR REPLACE TRIGGER "suppliers_protect_identity" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."protect_inventory_record_identity"();



CREATE OR REPLACE TRIGGER "suppliers_set_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "user_quick_links_set_updated_at" BEFORE UPDATE ON "public"."user_quick_links" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "accesorios_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_accessories"
    ADD CONSTRAINT "accesorios_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



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



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "campos_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_fields"
    ADD CONSTRAINT "campos_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_category_brands"
    ADD CONSTRAINT "categorias_componente_marcas_fk_categoria_componente_id_fkey" FOREIGN KEY ("fk_categoria_componente_id") REFERENCES "public"."component_categories"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_category_brands"
    ADD CONSTRAINT "categorias_componente_marcas_fk_marca_componente_id_fkey" FOREIGN KEY ("fk_marca_componente_id") REFERENCES "public"."component_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "colores_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_colors"
    ADD CONSTRAINT "colores_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitio_fk_default_measurement_unit__fkey" FOREIGN KEY ("fk_default_measurement_unit_id") REFERENCES "public"."measurement_units"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_definitions"
    ADD CONSTRAINT "component_attribute_definitions_component_type_id_fkey" FOREIGN KEY ("component_type_id") REFERENCES "public"."component_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_attribute_options"
    ADD CONSTRAINT "component_attribute_options_attribute_definition_id_fkey" FOREIGN KEY ("attribute_definition_id") REFERENCES "public"."component_attribute_definitions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."component_specifications"
    ADD CONSTRAINT "component_specifications_fk_component_attribute_definition_fkey" FOREIGN KEY ("fk_component_attribute_definition_id") REFERENCES "public"."component_attribute_definitions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_specifications"
    ADD CONSTRAINT "component_specifications_fk_device_component_id_fkey" FOREIGN KEY ("fk_device_component_id") REFERENCES "public"."device_components"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."component_specifications"
    ADD CONSTRAINT "component_specifications_fk_measurement_unit_id_fkey" FOREIGN KEY ("fk_measurement_unit_id") REFERENCES "public"."measurement_units"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."component_types"
    ADD CONSTRAINT "component_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_device_checklist_items"
    ADD CONSTRAINT "customer_device_checklist_items_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_connectivity"
    ADD CONSTRAINT "customer_device_connectivity_fk_connectivity_id_fkey" FOREIGN KEY ("fk_connectivity_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_connectivity"
    ADD CONSTRAINT "customer_device_connectivity_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_connectivity"
    ADD CONSTRAINT "customer_device_connectivity_fk_wifi_standard_id_fkey" FOREIGN KEY ("fk_wifi_standard_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_prof_fk_motherboard_form_factor_i_fkey" FOREIGN KEY ("fk_motherboard_form_factor_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profil_fk_display_refresh_rate_id_fkey" FOREIGN KEY ("fk_display_refresh_rate_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_charger_connector_id_fkey" FOREIGN KEY ("fk_charger_connector_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_display_resolution_id_fkey" FOREIGN KEY ("fk_display_resolution_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_display_size_id_fkey" FOREIGN KEY ("fk_display_size_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_display_technology_id_fkey" FOREIGN KEY ("fk_display_technology_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_motherboard_brand_id_fkey" FOREIGN KEY ("fk_motherboard_brand_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_motherboard_socket_id_fkey" FOREIGN KEY ("fk_motherboard_socket_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_processor_model_id_fkey" FOREIGN KEY ("fk_processor_model_id") REFERENCES "public"."processor_models"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_fk_psu_certification_id_fkey" FOREIGN KEY ("fk_psu_certification_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_gpu_brand_id_fkey" FOREIGN KEY ("gpu_brand_id") REFERENCES "public"."gpu_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_gpu_family_id_fkey" FOREIGN KEY ("gpu_family_id") REFERENCES "public"."gpu_families"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_hardware_profiles"
    ADD CONSTRAINT "customer_device_hardware_profiles_gpu_model_id_fkey" FOREIGN KEY ("gpu_model_id") REFERENCES "public"."gpu_models"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_operating_systems"
    ADD CONSTRAINT "customer_device_operating_systems_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_operating_systems"
    ADD CONSTRAINT "customer_device_operating_systems_fk_operating_system_id_fkey" FOREIGN KEY ("fk_operating_system_id") REFERENCES "public"."operating_systems"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ports"
    ADD CONSTRAINT "customer_device_ports_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ports"
    ADD CONSTRAINT "customer_device_ports_fk_port_connector_id_fkey" FOREIGN KEY ("fk_port_connector_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ports"
    ADD CONSTRAINT "customer_device_ports_fk_port_protocol_id_fkey" FOREIGN KEY ("fk_port_protocol_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ram_modules"
    ADD CONSTRAINT "customer_device_ram_modules_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ram_modules"
    ADD CONSTRAINT "customer_device_ram_modules_fk_ram_form_factor_id_fkey" FOREIGN KEY ("fk_ram_form_factor_id") REFERENCES "public"."ram_form_factors"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ram_modules"
    ADD CONSTRAINT "customer_device_ram_modules_fk_ram_speed_id_fkey" FOREIGN KEY ("fk_ram_speed_id") REFERENCES "public"."ram_speeds"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_ram_modules"
    ADD CONSTRAINT "customer_device_ram_modules_fk_ram_type_id_fkey" FOREIGN KEY ("fk_ram_type_id") REFERENCES "public"."ram_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_storage_drives"
    ADD CONSTRAINT "customer_device_storage_drives_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_storage_drives"
    ADD CONSTRAINT "customer_device_storage_drives_fk_storage_capacity_id_fkey" FOREIGN KEY ("fk_storage_capacity_id") REFERENCES "public"."storage_capacities"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_storage_drives"
    ADD CONSTRAINT "customer_device_storage_drives_fk_storage_form_factor_id_fkey" FOREIGN KEY ("fk_storage_form_factor_id") REFERENCES "public"."storage_form_factors"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_storage_drives"
    ADD CONSTRAINT "customer_device_storage_drives_fk_storage_interface_id_fkey" FOREIGN KEY ("fk_storage_interface_id") REFERENCES "public"."storage_interfaces"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_storage_drives"
    ADD CONSTRAINT "customer_device_storage_drives_fk_storage_type_id_fkey" FOREIGN KEY ("fk_storage_type_id") REFERENCES "public"."storage_types"("id") ON DELETE RESTRICT;



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



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "dependencias_campo_dispositiv_fk_tipo_dispositivo_campo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_campo_id") REFERENCES "public"."device_type_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_field_dependencies"
    ADD CONSTRAINT "dependencias_campo_dispositiv_fk_tipo_dispositivo_campo_pa_fkey" FOREIGN KEY ("fk_tipo_dispositivo_campo_padre_id") REFERENCES "public"."device_type_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_color_family_memberships"
    ADD CONSTRAINT "device_color_family_memberships_color_id_fkey" FOREIGN KEY ("color_id") REFERENCES "public"."device_colors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_color_family_memberships"
    ADD CONSTRAINT "device_color_family_memberships_family_id_fkey" FOREIGN KEY ("family_id") REFERENCES "public"."device_color_families"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_components"
    ADD CONSTRAINT "device_components_fk_component_type_id_fkey" FOREIGN KEY ("fk_component_type_id") REFERENCES "public"."component_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_components"
    ADD CONSTRAINT "device_components_fk_customer_device_id_fkey" FOREIGN KEY ("fk_customer_device_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_diagnostic_tests"
    ADD CONSTRAINT "device_type_diagnostic_tests_diagnostic_test_type_id_fkey" FOREIGN KEY ("diagnostic_test_type_id") REFERENCES "public"."diagnostic_test_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_services"
    ADD CONSTRAINT "device_type_services_technical_service_id_fkey" FOREIGN KEY ("technical_service_id") REFERENCES "public"."technical_services"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."diagnostic_test_types"
    ADD CONSTRAINT "diagnostic_test_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_diagnostics"
    ADD CONSTRAINT "diagnosticos_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_diagnostics"
    ADD CONSTRAINT "diagnosticos_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_diagnostics"
    ADD CONSTRAINT "diagnosticos_dispositivo_fk_recepcion_dispositivo_id_fkey" FOREIGN KEY ("fk_recepcion_dispositivo_id") REFERENCES "public"."device_receptions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_accessories"
    ADD CONSTRAINT "dispositivos_clientes_accesori_fk_accesorio_dispositivo_id_fkey" FOREIGN KEY ("fk_accesorio_dispositivo_id") REFERENCES "public"."device_accessories"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_accessories"
    ADD CONSTRAINT "dispositivos_clientes_accesorios_fk_dispositivo_cliente_id_fkey" FOREIGN KEY ("fk_dispositivo_cliente_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "dispositivos_clientes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "dispositivos_clientes_fk_color_dispositivo_id_fkey" FOREIGN KEY ("fk_color_dispositivo_id") REFERENCES "public"."device_colors"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "dispositivos_clientes_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "dispositivos_clientes_fk_tipo_dispositivo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "fk_customer_devices_motherboard_model_type" FOREIGN KEY ("fk_motherboard_model_id", "fk_tipo_dispositivo_id") REFERENCES "public"."motherboard_model_device_types"("motherboard_model_id", "device_type_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "fk_dispositivos_clientes_cliente_organizacion" FOREIGN KEY ("fk_cliente_id", "fk_organizacion_id") REFERENCES "public"."customers"("id", "organization_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "fk_dispositivos_clientes_marca_dispositivo" FOREIGN KEY ("fk_marca_dispositivo_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "fk_dispositivos_clientes_modelo_tipo_marca" FOREIGN KEY ("fk_modelo_dispositivo_id", "fk_tipo_dispositivo_id", "fk_marca_dispositivo_id") REFERENCES "public"."device_models"("id", "fk_tipo_dispositivo_id", "fk_marca_dispositivo_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "fk_dispositivos_clientes_tipo_marca" FOREIGN KEY ("fk_tipo_dispositivo_id", "fk_marca_dispositivo_id") REFERENCES "public"."device_type_brands"("fk_tipo_dispositivo_id", "fk_marca_dispositivo_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_devices"
    ADD CONSTRAINT "fk_dispositivos_clientes_variante_modelo" FOREIGN KEY ("fk_variante_modelo_dispositivo_id", "fk_modelo_dispositivo_id") REFERENCES "public"."device_model_variants"("id", "fk_modelo_dispositivo_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."processor_families"
    ADD CONSTRAINT "fk_familias_procesador_marca" FOREIGN KEY ("fk_marca_procesador_id") REFERENCES "public"."processor_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_models"
    ADD CONSTRAINT "fk_modelos_componente_categoria_marca" FOREIGN KEY ("fk_categoria_componente_id", "fk_marca_componente_id") REFERENCES "public"."component_category_brands"("fk_categoria_componente_id", "fk_marca_componente_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "fk_modelos_dispositivo_tipo_marca" FOREIGN KEY ("fk_tipo_dispositivo_id", "fk_marca_dispositivo_id") REFERENCES "public"."device_type_brands"("fk_tipo_dispositivo_id", "fk_marca_dispositivo_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "fk_recepciones_dispositivos_dispositivo_organizacion" FOREIGN KEY ("fk_dispositivo_cliente_id", "fk_organizacion_id") REFERENCES "public"."customer_devices"("id", "fk_organizacion_id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "fotos_recepcion_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reception_photos"
    ADD CONSTRAINT "fotos_recepcion_fk_recepcion_dispositivo_id_fkey" FOREIGN KEY ("fk_recepcion_dispositivo_id") REFERENCES "public"."device_receptions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."gpu_families"
    ADD CONSTRAINT "gpu_families_fk_gpu_brand_id_fkey" FOREIGN KEY ("fk_gpu_brand_id") REFERENCES "public"."gpu_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."gpu_models"
    ADD CONSTRAINT "gpu_models_fk_gpu_family_id_fkey" FOREIGN KEY ("fk_gpu_family_id") REFERENCES "public"."gpu_families"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."hardware_catalog_items"
    ADD CONSTRAINT "hardware_catalog_items_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."hardware_catalog_items"("id") ON DELETE RESTRICT;



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



ALTER TABLE ONLY "public"."component_brands"
    ADD CONSTRAINT "marcas_componente_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."component_brands"
    ADD CONSTRAINT "marcas_componente_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "marcas_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_brands"
    ADD CONSTRAINT "marcas_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."component_models"
    ADD CONSTRAINT "modelos_componente_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."component_models"
    ADD CONSTRAINT "modelos_componente_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "modelos_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "modelos_dispositivo_fk_marca_dispositivo_id_fkey" FOREIGN KEY ("fk_marca_dispositivo_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "modelos_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_models"
    ADD CONSTRAINT "modelos_dispositivo_fk_tipo_dispositivo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "modelos_procesador_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "modelos_procesador_fk_familia_procesador_id_fkey" FOREIGN KEY ("fk_familia_procesador_id") REFERENCES "public"."processor_families"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "modelos_procesador_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."motherboard_manufacturers"
    ADD CONSTRAINT "motherboard_manufacturers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."motherboard_manufacturers"
    ADD CONSTRAINT "motherboard_manufacturers_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."motherboard_model_device_types"
    ADD CONSTRAINT "motherboard_model_device_types_device_type_id_fkey" FOREIGN KEY ("device_type_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."motherboard_model_device_types"
    ADD CONSTRAINT "motherboard_model_device_types_motherboard_model_id_fkey" FOREIGN KEY ("motherboard_model_id") REFERENCES "public"."motherboard_models"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."motherboard_models"
    ADD CONSTRAINT "motherboard_models_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."motherboard_models"
    ADD CONSTRAINT "motherboard_models_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."motherboard_models"
    ADD CONSTRAINT "motherboard_models_motherboard_manufacturer_id_fkey" FOREIGN KEY ("motherboard_manufacturer_id") REFERENCES "public"."motherboard_manufacturers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."neighborhoods"
    ADD CONSTRAINT "neighborhoods_locality_id_fkey" FOREIGN KEY ("locality_id") REFERENCES "public"."localities"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "opciones_campo_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_field_options"
    ADD CONSTRAINT "opciones_campo_dispositivo_fk_campo_dispositivo_id_fkey" FOREIGN KEY ("fk_campo_dispositivo_id") REFERENCES "public"."device_fields"("id") ON DELETE RESTRICT;



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



ALTER TABLE ONLY "public"."processor_generations"
    ADD CONSTRAINT "processor_generations_fk_processor_family_id_fkey" FOREIGN KEY ("fk_processor_family_id") REFERENCES "public"."processor_families"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."processor_models"
    ADD CONSTRAINT "processor_models_fk_processor_generation_id_fkey" FOREIGN KEY ("fk_processor_generation_id") REFERENCES "public"."processor_generations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."processor_specifications"
    ADD CONSTRAINT "processor_specifications_fk_processor_model_id_fkey" FOREIGN KEY ("fk_processor_model_id") REFERENCES "public"."processor_models"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."provinces"
    ADD CONSTRAINT "provinces_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "public"."countries"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."ram_speeds"
    ADD CONSTRAINT "ram_speeds_fk_ram_type_id_fkey" FOREIGN KEY ("fk_ram_type_id") REFERENCES "public"."ram_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "recepciones_dispositivos_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_receptions"
    ADD CONSTRAINT "recepciones_dispositivos_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reception_evidence_types"
    ADD CONSTRAINT "reception_evidence_types_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "resultados_control_recepcion_fk_control_recepcion_disposit_fkey" FOREIGN KEY ("fk_control_recepcion_dispositivo_id") REFERENCES "public"."device_reception_controls"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reception_inspection_items"
    ADD CONSTRAINT "resultados_control_recepcion_fk_recepcion_dispositivo_id_fkey" FOREIGN KEY ("fk_recepcion_dispositivo_id") REFERENCES "public"."device_receptions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "secciones_formulario_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_form_sections"
    ADD CONSTRAINT "secciones_formulario_dispositivo_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."service_categories"
    ADD CONSTRAINT "service_categories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



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



ALTER TABLE ONLY "public"."storage_types"
    ADD CONSTRAINT "tipos_almacenamiento_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."storage_types"
    ADD CONSTRAINT "tipos_almacenamiento_fk_organizacion_id_fkey" FOREIGN KEY ("fk_organizacion_id") REFERENCES "public"."organizations"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "tipos_dispositivo_campos_fk_campo_dispositivo_id_fkey" FOREIGN KEY ("fk_campo_dispositivo_id") REFERENCES "public"."device_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "tipos_dispositivo_campos_fk_seccion_formulario_dispositivo_fkey" FOREIGN KEY ("fk_seccion_formulario_dispositivo_id") REFERENCES "public"."device_form_sections"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_fields"
    ADD CONSTRAINT "tipos_dispositivo_campos_fk_tipo_dispositivo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_reception_controls"
    ADD CONSTRAINT "tipos_dispositivo_controles_r_fk_control_recepcion_disposi_fkey" FOREIGN KEY ("fk_control_recepcion_dispositivo_id") REFERENCES "public"."device_reception_controls"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_reception_controls"
    ADD CONSTRAINT "tipos_dispositivo_controles_recepci_fk_tipo_dispositivo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_brands"
    ADD CONSTRAINT "tipos_dispositivo_marcas_fk_marca_dispositivo_id_fkey" FOREIGN KEY ("fk_marca_dispositivo_id") REFERENCES "public"."device_brands"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_type_brands"
    ADD CONSTRAINT "tipos_dispositivo_marcas_fk_tipo_dispositivo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_id") REFERENCES "public"."device_types"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_quick_links"
    ADD CONSTRAINT "user_quick_links_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "valores_campos_dispositivo_fk_dispositivo_cliente_id_fkey" FOREIGN KEY ("fk_dispositivo_cliente_id") REFERENCES "public"."customer_devices"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "valores_campos_dispositivo_fk_opcion_campo_dispositivo_id_fkey" FOREIGN KEY ("fk_opcion_campo_dispositivo_id") REFERENCES "public"."device_field_options"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."customer_device_field_values"
    ADD CONSTRAINT "valores_campos_dispositivo_fk_tipo_dispositivo_campo_id_fkey" FOREIGN KEY ("fk_tipo_dispositivo_campo_id") REFERENCES "public"."device_type_fields"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "variantes_modelo_dispositivo_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."device_model_variants"
    ADD CONSTRAINT "variantes_modelo_dispositivo_fk_modelo_dispositivo_id_fkey" FOREIGN KEY ("fk_modelo_dispositivo_id") REFERENCES "public"."device_models"("id") ON DELETE RESTRICT;



CREATE POLICY "accesorios_dispositivo_lectura" ON "public"."device_accessories" FOR SELECT TO "authenticated" USING (("activo" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



ALTER TABLE "public"."account_deletion_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "account_deletion_requests_self_select" ON "public"."account_deletion_requests" FOR SELECT TO "authenticated" USING ((("target_user_id" = "auth"."uid"()) OR ("requested_by" = "auth"."uid"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("subject_type" = 'ORGANIZATION'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'OWNER'::"public"."app_role") AND ("p"."status" = 'ACTIVE'::"public"."profile_status") AND ("p"."organization_id" = "account_deletion_requests"."organization_id")))))));



ALTER TABLE "public"."audit_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_events_select" ON "public"."audit_events" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("organization_id" = "public"."current_organization_id"()) AND ("public"."current_app_role"() = 'OWNER'::"public"."app_role"))));



ALTER TABLE "public"."auth_rate_limits" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "campos_dispositivo_lectura" ON "public"."device_fields" FOR SELECT USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



CREATE POLICY "categorias_componente_lectura" ON "public"."component_categories" FOR SELECT TO "authenticated" USING ("activo");



CREATE POLICY "categorias_componente_marcas_lectura" ON "public"."component_category_brands" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."component_brands" "m"
  WHERE (("m"."id" = "component_category_brands"."fk_marca_componente_id") AND "m"."activo" AND (("m"."alcance" = 'GLOBAL'::"text") OR ("m"."fk_organizacion_id" = "public"."current_organization_id"()))))));



CREATE POLICY "colores_dispositivo_lectura" ON "public"."device_colors" FOR SELECT TO "authenticated" USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



ALTER TABLE "public"."component_attribute_definitions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_attribute_definitions_read" ON "public"."component_attribute_definitions" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."component_attribute_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_attribute_options_read" ON "public"."component_attribute_options" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."component_brands" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."component_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."component_category_brands" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."component_models" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."component_specifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_specifications_tenant" ON "public"."component_specifications" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."device_components" "c"
     JOIN "public"."customer_devices" "d" ON (("d"."id" = "c"."fk_customer_device_id")))
  WHERE (("c"."id" = "component_specifications"."fk_device_component_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."device_components" "c"
     JOIN "public"."customer_devices" "d" ON (("d"."id" = "c"."fk_customer_device_id")))
  WHERE (("c"."id" = "component_specifications"."fk_device_component_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."component_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "component_types_read" ON "public"."component_types" FOR SELECT TO "authenticated" USING (("is_active" AND (("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"()))));



CREATE POLICY "controles_recepcion_dispositivo_lectura" ON "public"."device_reception_controls" FOR SELECT USING ("is_active");



ALTER TABLE "public"."countries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "countries_read" ON "public"."countries" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."customer_device_accessories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_device_checklist_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_checklist_items_read" ON "public"."customer_device_checklist_items" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_checklist_items"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_device_connectivity" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_connectivity_read" ON "public"."customer_device_connectivity" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_connectivity"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_device_field_values" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_device_hardware_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_hardware_profiles_read" ON "public"."customer_device_hardware_profiles" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_hardware_profiles"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_device_operating_systems" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_operating_systems_tenant" ON "public"."customer_device_operating_systems" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_operating_systems"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_operating_systems"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_device_ports" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_ports_read" ON "public"."customer_device_ports" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_ports"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_device_ram_modules" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_ram_modules_read" ON "public"."customer_device_ram_modules" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_ram_modules"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_device_storage_drives" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customer_device_storage_drives_read" ON "public"."customer_device_storage_drives" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_storage_drives"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."customer_devices" ENABLE ROW LEVEL SECURITY;


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



CREATE POLICY "dependencias_campo_dispositivo_lectura" ON "public"."device_field_dependencies" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."device_type_fields" "tc"
  WHERE (("tc"."id" = "device_field_dependencies"."fk_tipo_dispositivo_campo_id") AND "tc"."is_active"))));



ALTER TABLE "public"."device_accessories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_brands" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_color_families" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_color_families_read" ON "public"."device_color_families" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."device_color_family_memberships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_color_family_memberships_read" ON "public"."device_color_family_memberships" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "public"."device_colors" "c"
  WHERE (("c"."id" = "device_color_family_memberships"."color_id") AND "c"."is_active" AND (("c"."alcance" = 'GLOBAL'::"text") OR ("c"."fk_organizacion_id" = "public"."current_organization_id"()))))) AND (EXISTS ( SELECT 1
   FROM "public"."device_color_families" "f"
  WHERE (("f"."id" = "device_color_family_memberships"."family_id") AND "f"."is_active")))));



ALTER TABLE "public"."device_colors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_components" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_components_tenant" ON "public"."device_components" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "device_components"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "device_components"."fk_customer_device_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."device_diagnostics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_field_dependencies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_field_options" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_fields" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_form_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_model_variants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_models" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_reception_controls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_receptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_type_brands" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_type_diagnostic_tests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_diagnostic_tests_read" ON "public"."device_type_diagnostic_tests" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_type_fields" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_type_reception_controls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_type_services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_type_services_read" ON "public"."device_type_services" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."device_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."diagnostic_result_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "diagnostic_result_types_read" ON "public"."diagnostic_result_types" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."diagnostic_test_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "diagnostic_test_types_read" ON "public"."diagnostic_test_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



CREATE POLICY "diagnosticos_dispositivo_lectura_organizacion" ON "public"."device_diagnostics" FOR SELECT TO "authenticated" USING (("fk_organizacion_id" = "public"."current_organization_id"()));



CREATE POLICY "dispositivos_clientes_accesorios_lectura" ON "public"."customer_device_accessories" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_accessories"."fk_dispositivo_cliente_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



CREATE POLICY "dispositivos_clientes_lectura_organizacion" ON "public"."customer_devices" FOR SELECT TO "authenticated" USING (("fk_organizacion_id" = "public"."current_organization_id"()));



CREATE POLICY "familias_procesador_lectura" ON "public"."processor_families" FOR SELECT TO "authenticated" USING ("activo");



CREATE POLICY "fotos_recepcion_lectura_organizacion" ON "public"."reception_photos" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."device_receptions" "r"
  WHERE (("r"."id" = "reception_photos"."fk_recepcion_dispositivo_id") AND ("r"."fk_organizacion_id" = "public"."current_organization_id"())))));



ALTER TABLE "public"."gpu_brands" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gpu_families" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gpu_models" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hardware_catalog_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hardware_catalog_items_read" ON "public"."hardware_catalog_items" FOR SELECT TO "authenticated" USING ("is_active");



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



CREATE POLICY "marcas_componente_lectura" ON "public"."component_brands" FOR SELECT TO "authenticated" USING (("activo" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



CREATE POLICY "marcas_dispositivo_lectura" ON "public"."device_brands" FOR SELECT USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



CREATE POLICY "marcas_procesador_lectura" ON "public"."processor_brands" FOR SELECT TO "authenticated" USING ("activo");



ALTER TABLE "public"."measurement_units" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "measurement_units_read" ON "public"."measurement_units" FOR SELECT TO "authenticated" USING ("is_active");



CREATE POLICY "modelos_componente_lectura" ON "public"."component_models" FOR SELECT TO "authenticated" USING (("activo" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



CREATE POLICY "modelos_dispositivo_lectura" ON "public"."device_models" FOR SELECT USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



CREATE POLICY "modelos_procesador_lectura" ON "public"."processor_models" FOR SELECT TO "authenticated" USING (("activo" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



ALTER TABLE "public"."motherboard_manufacturers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "motherboard_manufacturers_read" ON "public"."motherboard_manufacturers" FOR SELECT TO "authenticated" USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



ALTER TABLE "public"."motherboard_model_device_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "motherboard_model_device_types_read" ON "public"."motherboard_model_device_types" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."motherboard_models" "m"
  WHERE (("m"."id" = "motherboard_model_device_types"."motherboard_model_id") AND "m"."is_active" AND (("m"."alcance" = 'GLOBAL'::"text") OR ("m"."fk_organizacion_id" = "public"."current_organization_id"()))))));



ALTER TABLE "public"."motherboard_models" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "motherboard_models_read" ON "public"."motherboard_models" FOR SELECT TO "authenticated" USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



ALTER TABLE "public"."neighborhoods" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "neighborhoods_read" ON "public"."neighborhoods" FOR SELECT TO "authenticated" USING ("is_active");



CREATE POLICY "opciones_campo_dispositivo_lectura" ON "public"."device_field_options" FOR SELECT TO "authenticated" USING (("is_active" AND (EXISTS ( SELECT 1
   FROM "public"."device_fields" "c"
  WHERE (("c"."id" = "device_field_options"."fk_campo_dispositivo_id") AND "c"."is_active" AND (("c"."alcance" = 'GLOBAL'::"text") OR ("c"."fk_organizacion_id" = "public"."current_organization_id"())))))));



ALTER TABLE "public"."operating_systems" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "operating_systems_read" ON "public"."operating_systems" FOR SELECT TO "authenticated" USING (("is_active" AND (("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"()))));



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


ALTER TABLE "public"."processor_brands" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."processor_families" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."processor_generations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "processor_generations_read" ON "public"."processor_generations" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."processor_models" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."processor_specifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "processor_specifications_read" ON "public"."processor_specifications" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR ("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR (("public"."current_app_role"() = 'OWNER'::"public"."app_role") AND ("organization_id" = "public"."current_organization_id"()))));



CREATE POLICY "profiles_update_self" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"())) WITH CHECK (("id" = "auth"."uid"()));



ALTER TABLE "public"."provinces" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "provinces_read" ON "public"."provinces" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."ram_form_factors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ram_form_factors_read" ON "public"."ram_form_factors" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."ram_speeds" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ram_speeds_read" ON "public"."ram_speeds" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."ram_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ram_types_read" ON "public"."ram_types" FOR SELECT TO "authenticated" USING ("is_active");



CREATE POLICY "recepciones_dispositivos_lectura_organizacion" ON "public"."device_receptions" FOR SELECT TO "authenticated" USING (("fk_organizacion_id" = "public"."current_organization_id"()));



ALTER TABLE "public"."reception_evidence_types" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reception_evidence_types_read" ON "public"."reception_evidence_types" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."reception_inspection_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reception_photos" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "resultados_control_recepcion_organizacion" ON "public"."reception_inspection_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."device_receptions" "r"
  WHERE (("r"."id" = "reception_inspection_items"."fk_recepcion_dispositivo_id") AND ("r"."fk_organizacion_id" = "public"."current_organization_id"())))));



CREATE POLICY "secciones_formulario_dispositivo_lectura" ON "public"."device_form_sections" FOR SELECT USING (("is_active" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



ALTER TABLE "public"."service_categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_categories_read" ON "public"."service_categories" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



ALTER TABLE "public"."storage_capacities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storage_capacities_read" ON "public"."storage_capacities" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."storage_form_factors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storage_form_factors_read" ON "public"."storage_form_factors" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."storage_interfaces" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "storage_interfaces_read" ON "public"."storage_interfaces" FOR SELECT TO "authenticated" USING ("is_active");



ALTER TABLE "public"."storage_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "suppliers_insert" ON "public"."suppliers" FOR INSERT TO "authenticated" WITH CHECK (("public"."has_inventory_owner_access"("organization_id") AND ("created_by" = "auth"."uid"())));



CREATE POLICY "suppliers_select" ON "public"."suppliers" FOR SELECT TO "authenticated" USING ((("public"."current_app_role"() = 'SUPERADMIN'::"public"."app_role") OR "public"."has_inventory_owner_access"("organization_id")));



CREATE POLICY "suppliers_update" ON "public"."suppliers" FOR UPDATE TO "authenticated" USING ("public"."has_inventory_owner_access"("organization_id")) WITH CHECK ("public"."has_inventory_owner_access"("organization_id"));



ALTER TABLE "public"."technical_services" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "technical_services_read" ON "public"."technical_services" FOR SELECT TO "authenticated" USING ((("organization_id" IS NULL) OR ("organization_id" = "public"."current_organization_id"())));



CREATE POLICY "tipos_almacenamiento_lectura" ON "public"."storage_types" FOR SELECT TO "authenticated" USING (("activo" AND (("alcance" = 'GLOBAL'::"text") OR ("fk_organizacion_id" = "public"."current_organization_id"()))));



CREATE POLICY "tipos_dispositivo_campos_lectura" ON "public"."device_type_fields" FOR SELECT TO "authenticated" USING (("is_active" AND (EXISTS ( SELECT 1
   FROM "public"."device_fields" "c"
  WHERE (("c"."id" = "device_type_fields"."fk_campo_dispositivo_id") AND "c"."is_active" AND (("c"."alcance" = 'GLOBAL'::"text") OR ("c"."fk_organizacion_id" = "public"."current_organization_id"())))))));



CREATE POLICY "tipos_dispositivo_controles_recepcion_lectura" ON "public"."device_type_reception_controls" FOR SELECT USING ("is_active");



CREATE POLICY "tipos_dispositivo_lectura" ON "public"."device_types" FOR SELECT USING ("is_active");



CREATE POLICY "tipos_dispositivo_marcas_lectura" ON "public"."device_type_brands" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."device_brands" "m"
  WHERE (("m"."id" = "device_type_brands"."fk_marca_dispositivo_id") AND (("m"."alcance" = 'GLOBAL'::"text") OR ("m"."fk_organizacion_id" = "public"."current_organization_id"()))))));



ALTER TABLE "public"."user_quick_links" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_quick_links_delete_own" ON "public"."user_quick_links" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_insert_own" ON "public"."user_quick_links" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_select_own" ON "public"."user_quick_links" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_quick_links_update_own" ON "public"."user_quick_links" FOR UPDATE TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "valores_campos_dispositivo_organizacion" ON "public"."customer_device_field_values" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."customer_devices" "d"
  WHERE (("d"."id" = "customer_device_field_values"."fk_dispositivo_cliente_id") AND ("d"."fk_organizacion_id" = "public"."current_organization_id"())))));



CREATE POLICY "variantes_modelo_dispositivo_lectura" ON "public"."device_model_variants" FOR SELECT TO "authenticated" USING (("is_active" AND (EXISTS ( SELECT 1
   FROM "public"."device_models" "m"
  WHERE (("m"."id" = "device_model_variants"."fk_modelo_dispositivo_id") AND "m"."is_active" AND (("m"."alcance" = 'GLOBAL'::"text") OR ("m"."fk_organizacion_id" = "public"."current_organization_id"())))))));



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



REVOKE ALL ON FUNCTION "public"."confirmar_recepcion_dispositivo"("p_dispositivo_cliente_id" "uuid", "p_problema_informado" "text", "p_observaciones" "text", "p_resultados" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirmar_recepcion_dispositivo"("p_dispositivo_cliente_id" "uuid", "p_problema_informado" "text", "p_observaciones" "text", "p_resultados" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirmar_recepcion_dispositivo"("p_dispositivo_cliente_id" "uuid", "p_problema_informado" "text", "p_observaciones" "text", "p_resultados" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."consume_auth_rate_limit"("p_action" "text", "p_key_hash" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalizar_nombre_catalogo"("p_valor" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalizar_nombre_catalogo"("p_valor" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalizar_nombre_catalogo"("p_valor" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_accessories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_accessories" TO "authenticated";
GRANT ALL ON TABLE "public"."device_accessories" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_accesorio_dispositivo"("p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_accesorio_dispositivo"("p_nombre" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_accesorio_dispositivo"("p_nombre" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_colors" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_colors" TO "authenticated";
GRANT ALL ON TABLE "public"."device_colors" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_color_dispositivo"("p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_color_dispositivo"("p_nombre" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."crear_color_dispositivo"("p_nombre" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."crear_dispositivo_cliente"("p_cliente_id" "uuid", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid", "p_modelo_dispositivo_id" "uuid", "p_variante_modelo_dispositivo_id" "uuid", "p_color_dispositivo_id" "uuid", "p_numero_serie" "text", "p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_modelo_procesador_id" "uuid", "p_atributos" "jsonb", "p_memorias" "jsonb", "p_almacenamientos" "jsonb", "p_accesorios" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_dispositivo_cliente"("p_cliente_id" "uuid", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid", "p_modelo_dispositivo_id" "uuid", "p_variante_modelo_dispositivo_id" "uuid", "p_color_dispositivo_id" "uuid", "p_numero_serie" "text", "p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_modelo_procesador_id" "uuid", "p_atributos" "jsonb", "p_memorias" "jsonb", "p_almacenamientos" "jsonb", "p_accesorios" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_dispositivo_cliente"("p_cliente_id" "uuid", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid", "p_modelo_dispositivo_id" "uuid", "p_variante_modelo_dispositivo_id" "uuid", "p_color_dispositivo_id" "uuid", "p_numero_serie" "text", "p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_modelo_procesador_id" "uuid", "p_atributos" "jsonb", "p_memorias" "jsonb", "p_almacenamientos" "jsonb", "p_accesorios" "jsonb") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_brands" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."component_brands" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_marca_componente"("p_categoria" "text", "p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_marca_componente"("p_categoria" "text", "p_nombre" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_marca_componente"("p_categoria" "text", "p_nombre" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_brands" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."device_brands" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_marca_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_marca_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_marca_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_models" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_models" TO "authenticated";
GRANT ALL ON TABLE "public"."component_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_modelo_componente"("p_categoria" "text", "p_marca_componente_id" "uuid", "p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_modelo_componente"("p_categoria" "text", "p_marca_componente_id" "uuid", "p_nombre" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_modelo_componente"("p_categoria" "text", "p_marca_componente_id" "uuid", "p_nombre" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_models" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_models" TO "authenticated";
GRANT ALL ON TABLE "public"."device_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_modelo_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_modelo_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_modelo_dispositivo"("p_nombre" "text", "p_tipo_dispositivo_id" "uuid", "p_marca_dispositivo_id" "uuid") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_models" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_models" TO "authenticated";
GRANT ALL ON TABLE "public"."processor_models" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_modelo_procesador"("p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_modelo_procesador"("p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_nombre" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_modelo_procesador"("p_marca_procesador_id" "uuid", "p_familia_procesador_id" "uuid", "p_nombre" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_types" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_types" TO "authenticated";
GRANT ALL ON TABLE "public"."storage_types" TO "service_role";



REVOKE ALL ON FUNCTION "public"."crear_tipo_almacenamiento"("p_nombre" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."crear_tipo_almacenamiento"("p_nombre" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_tipo_almacenamiento"("p_nombre" "text") TO "service_role";



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



REVOKE ALL ON FUNCTION "public"."delete_private_device_brand"("p_device_type_id" "uuid", "p_device_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_private_device_brand"("p_device_type_id" "uuid", "p_device_brand_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_private_device_brand"("p_device_type_id" "uuid", "p_device_brand_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_due_account_deletions"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_due_account_deletions"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_initial_organization_setup"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_initial_organization_setup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."finalize_initial_organization_setup"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_compatible_processor_brands"("p_device_type_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_compatible_processor_brands"("p_device_type_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_compatible_processor_brands"("p_device_type_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_compatible_processor_families"("p_device_type_code" "text", "p_brand_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_compatible_processor_families"("p_device_type_code" "text", "p_brand_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_compatible_processor_families"("p_device_type_code" "text", "p_brand_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_compatible_processor_generations"("p_device_type_code" "text", "p_brand_id" "uuid", "p_family_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_compatible_processor_generations"("p_device_type_code" "text", "p_brand_id" "uuid", "p_family_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_compatible_processor_generations"("p_device_type_code" "text", "p_brand_id" "uuid", "p_family_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_compatible_processor_models"("p_device_type_code" "text", "p_family_id" "uuid", "p_generation_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_compatible_processor_models"("p_device_type_code" "text", "p_family_id" "uuid", "p_generation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_compatible_processor_models"("p_device_type_code" "text", "p_family_id" "uuid", "p_generation_id" "uuid") TO "service_role";



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



GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_catalog_name"("p_value" "text") TO "service_role";



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



REVOKE ALL ON FUNCTION "public"."registrar_foto_recepcion"("p_recepcion_dispositivo_id" "uuid", "p_ruta_storage" "text", "p_descripcion" "text", "p_clave_control" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."registrar_foto_recepcion"("p_recepcion_dispositivo_id" "uuid", "p_ruta_storage" "text", "p_descripcion" "text", "p_clave_control" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_foto_recepcion"("p_recepcion_dispositivo_id" "uuid", "p_ruta_storage" "text", "p_descripcion" "text", "p_clave_control" "text") TO "service_role";



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



REVOKE ALL ON FUNCTION "public"."save_customer_device_identification"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_customer_device_identification"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_customer_device_identification"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_customer_device_step_two"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid", "p_attributes" "jsonb", "p_ram_modules" "jsonb", "p_storage_drives" "jsonb", "p_ports" "jsonb", "p_accessory_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_customer_device_step_two"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid", "p_attributes" "jsonb", "p_ram_modules" "jsonb", "p_storage_drives" "jsonb", "p_ports" "jsonb", "p_accessory_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_customer_device_step_two"("p_customer_id" "uuid", "p_device_type_id" "uuid", "p_device_brand_id" "uuid", "p_device_model_id" "uuid", "p_serial_number" "text", "p_observations" "text", "p_customer_device_id" "uuid", "p_attributes" "jsonb", "p_ram_modules" "jsonb", "p_storage_drives" "jsonb", "p_ports" "jsonb", "p_accessory_ids" "uuid"[]) TO "service_role";



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



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_categories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."component_categories" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_category_brands" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_category_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."component_category_brands" TO "service_role";



GRANT ALL ON TABLE "public"."component_specifications" TO "anon";
GRANT ALL ON TABLE "public"."component_specifications" TO "authenticated";
GRANT ALL ON TABLE "public"."component_specifications" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_types" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."component_types" TO "authenticated";
GRANT ALL ON TABLE "public"."component_types" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."countries" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."countries" TO "authenticated";
GRANT ALL ON TABLE "public"."countries" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_accessories" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_accessories" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_accessories" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_checklist_items" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_checklist_items" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_checklist_items" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_connectivity" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_connectivity" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_connectivity" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_field_values" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_field_values" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_field_values" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_hardware_profiles" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_hardware_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_hardware_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."customer_device_operating_systems" TO "anon";
GRANT ALL ON TABLE "public"."customer_device_operating_systems" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_operating_systems" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_ports" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_device_ports" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_ports" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."customer_device_ram_modules" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_ram_modules" TO "service_role";



GRANT SELECT,MAINTAIN ON TABLE "public"."customer_device_storage_drives" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_device_storage_drives" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_devices" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."customer_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_devices" TO "service_role";



GRANT ALL ON TABLE "public"."customer_user_links" TO "anon";
GRANT ALL ON TABLE "public"."customer_user_links" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_user_links" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."device_color_families" TO "anon";
GRANT ALL ON TABLE "public"."device_color_families" TO "authenticated";
GRANT ALL ON TABLE "public"."device_color_families" TO "service_role";



GRANT ALL ON TABLE "public"."device_color_family_memberships" TO "anon";
GRANT ALL ON TABLE "public"."device_color_family_memberships" TO "authenticated";
GRANT ALL ON TABLE "public"."device_color_family_memberships" TO "service_role";



GRANT ALL ON TABLE "public"."device_components" TO "anon";
GRANT ALL ON TABLE "public"."device_components" TO "authenticated";
GRANT ALL ON TABLE "public"."device_components" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_diagnostics" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_diagnostics" TO "authenticated";
GRANT ALL ON TABLE "public"."device_diagnostics" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_field_dependencies" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_field_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."device_field_dependencies" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_field_options" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_field_options" TO "authenticated";
GRANT ALL ON TABLE "public"."device_field_options" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_fields" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."device_fields" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_form_sections" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_form_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."device_form_sections" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_model_variants" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_model_variants" TO "authenticated";
GRANT ALL ON TABLE "public"."device_model_variants" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_reception_controls" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_reception_controls" TO "authenticated";
GRANT ALL ON TABLE "public"."device_reception_controls" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_receptions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_receptions" TO "authenticated";
GRANT ALL ON TABLE "public"."device_receptions" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_type_brands" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_type_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_brands" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "anon";
GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_diagnostic_tests" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_type_fields" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_type_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_fields" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_type_reception_controls" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_type_reception_controls" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_reception_controls" TO "service_role";



GRANT ALL ON TABLE "public"."device_type_services" TO "anon";
GRANT ALL ON TABLE "public"."device_type_services" TO "authenticated";
GRANT ALL ON TABLE "public"."device_type_services" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_types" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."device_types" TO "authenticated";
GRANT ALL ON TABLE "public"."device_types" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "anon";
GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostic_result_types" TO "service_role";



GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "anon";
GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "authenticated";
GRANT ALL ON TABLE "public"."diagnostic_test_types" TO "service_role";



GRANT ALL ON TABLE "public"."gpu_brands" TO "anon";
GRANT ALL ON TABLE "public"."gpu_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."gpu_brands" TO "service_role";



GRANT ALL ON TABLE "public"."gpu_families" TO "anon";
GRANT ALL ON TABLE "public"."gpu_families" TO "authenticated";
GRANT ALL ON TABLE "public"."gpu_families" TO "service_role";



GRANT ALL ON TABLE "public"."gpu_models" TO "anon";
GRANT ALL ON TABLE "public"."gpu_models" TO "authenticated";
GRANT ALL ON TABLE "public"."gpu_models" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."hardware_catalog_items" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."hardware_catalog_items" TO "authenticated";
GRANT ALL ON TABLE "public"."hardware_catalog_items" TO "service_role";



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



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."measurement_units" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."measurement_units" TO "authenticated";
GRANT ALL ON TABLE "public"."measurement_units" TO "service_role";



GRANT ALL ON TABLE "public"."motherboard_manufacturers" TO "service_role";
GRANT SELECT ON TABLE "public"."motherboard_manufacturers" TO "authenticated";



GRANT ALL ON TABLE "public"."motherboard_model_device_types" TO "service_role";
GRANT SELECT ON TABLE "public"."motherboard_model_device_types" TO "authenticated";



GRANT ALL ON TABLE "public"."motherboard_models" TO "service_role";
GRANT SELECT ON TABLE "public"."motherboard_models" TO "authenticated";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."neighborhoods" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."neighborhoods" TO "authenticated";
GRANT ALL ON TABLE "public"."neighborhoods" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."operating_systems" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."operating_systems" TO "authenticated";
GRANT ALL ON TABLE "public"."operating_systems" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organization_addresses" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organization_addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_addresses" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON TABLE "public"."password_history" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_brands" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_brands" TO "authenticated";
GRANT ALL ON TABLE "public"."processor_brands" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_families" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_families" TO "authenticated";
GRANT ALL ON TABLE "public"."processor_families" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_generations" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_generations" TO "authenticated";
GRANT ALL ON TABLE "public"."processor_generations" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_specifications" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."processor_specifications" TO "authenticated";
GRANT ALL ON TABLE "public"."processor_specifications" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."provinces" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."provinces" TO "authenticated";
GRANT ALL ON TABLE "public"."provinces" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ram_form_factors" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ram_form_factors" TO "authenticated";
GRANT ALL ON TABLE "public"."ram_form_factors" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ram_speeds" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ram_speeds" TO "authenticated";
GRANT ALL ON TABLE "public"."ram_speeds" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ram_types" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ram_types" TO "authenticated";
GRANT ALL ON TABLE "public"."ram_types" TO "service_role";



GRANT ALL ON TABLE "public"."reception_evidence_types" TO "anon";
GRANT ALL ON TABLE "public"."reception_evidence_types" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_evidence_types" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."reception_inspection_items" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."reception_inspection_items" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_inspection_items" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."reception_photos" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."reception_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."reception_photos" TO "service_role";



GRANT ALL ON TABLE "public"."service_categories" TO "anon";
GRANT ALL ON TABLE "public"."service_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."service_categories" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_capacities" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_capacities" TO "authenticated";
GRANT ALL ON TABLE "public"."storage_capacities" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_form_factors" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_form_factors" TO "authenticated";
GRANT ALL ON TABLE "public"."storage_form_factors" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_interfaces" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."storage_interfaces" TO "authenticated";
GRANT ALL ON TABLE "public"."storage_interfaces" TO "service_role";



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







