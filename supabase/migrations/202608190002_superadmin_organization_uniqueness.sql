-- Unicidad y validación fuerte para organizaciones creadas por SUPERADMIN.
update public.organizations
set
  name = regexp_replace(trim(name), '[[:space:]]+', ' ', 'g'),
  slug = lower(trim(slug));

alter table public.organizations drop constraint if exists organizations_slug_check;
alter table public.organizations
  add constraint organizations_name_format_check check (
    char_length(name) between 2 and 120
    and name ~ '^[[:alnum:]_ -]+$'
  ),
  add constraint organizations_slug_check check (
    char_length(slug) between 2 and 80
    and slug ~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$'
  );

create unique index organizations_name_normalized_key
on public.organizations (lower(regexp_replace(trim(name), '[[:space:]]+', ' ', 'g')));

create or replace function public.admin_create_organization(name text, slug text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text := regexp_replace(trim(name), '[[:space:]]+', ' ', 'g');
  v_slug text := lower(trim(slug));
begin
  if public.current_app_role() <> 'SUPERADMIN' then raise exception 'Forbidden'; end if;
  if char_length(v_name) not between 2 and 120 or v_name !~ '^[[:alnum:]_ -]+$' then
    raise exception 'Invalid organization name';
  end if;
  if char_length(v_slug) not between 2 and 80 or v_slug !~ '^[a-z0-9]+(?:[-_][a-z0-9]+)*$' then
    raise exception 'Invalid organization identifier';
  end if;

  insert into public.organizations (name, slug)
  values (v_name, v_slug)
  returning id into v_id;

  insert into public.audit_events (actor_user_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'ADMIN_ORGANIZATION_CREATED', 'ORGANIZATION', v_id, '{}'::jsonb);
  return v_id;
end;
$$;

comment on index public.organizations_name_normalized_key is 'Impide nombres duplicados ignorando mayúsculas, minúsculas y espacios repetidos.';
