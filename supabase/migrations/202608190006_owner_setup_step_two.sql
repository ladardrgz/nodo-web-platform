-- Paso 2 persistente del onboarding OWNER: contacto de la organización.
-- Reutiliza organizations.phone y organizations.contact_email.
create function public.save_initial_organization_step_two(
  p_phone text,
  p_contact_email text
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.save_initial_organization_step_two(text, text) from public, anon;
grant execute on function public.save_initial_organization_step_two(text, text) to authenticated;

comment on function public.save_initial_organization_step_two(text, text) is
  'Guarda únicamente teléfono E.164 y email de contacto del OWNER autenticado y avanza el onboarding al paso 3.';
