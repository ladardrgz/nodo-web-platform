-- Paso 1 persistente del onboarding OWNER: identidad de la organización.
alter table public.organizations
  add column if not exists initial_setup_step smallint;

update public.organizations
set initial_setup_step = case when initial_setup_completed then 4 else 1 end
where initial_setup_step is null;

alter table public.organizations
  alter column initial_setup_step set default 1,
  alter column initial_setup_step set not null;

alter table public.organizations drop constraint if exists organizations_initial_setup_step_check;
alter table public.organizations
  add constraint organizations_initial_setup_step_check check (initial_setup_step between 1 and 4);

-- La validación anterior no admitía denominaciones legales legítimas como S.R.L. o R&R.
alter table public.organizations drop constraint if exists organizations_name_format_check;
alter table public.organizations
  add constraint organizations_name_format_check check (
    char_length(name) between 2 and 120
    and name !~ '[<>]'
    and name !~ '[[:cntrl:]]'
  );

create function public.save_initial_organization_step_one(
  p_legal_name text,
  p_commercial_name text,
  p_logo_path text
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on function public.save_initial_organization_step_one(text, text, text) from public, anon;
grant execute on function public.save_initial_organization_step_one(text, text, text) to authenticated;

comment on column public.organizations.initial_setup_step is 'Próximo paso pendiente del onboarding; no reemplaza initial_setup_completed.';
comment on function public.save_initial_organization_step_one(text, text, text) is 'Guarda únicamente identidad y logo del OWNER autenticado y avanza el onboarding al paso 2.';
