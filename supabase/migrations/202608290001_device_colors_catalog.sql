-- Colores de dispositivos: catálogo común y extensiones privadas por organización.
create table public.device_colors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 80),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index device_colors_system_name_unique on public.device_colors (lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is null;
create unique index device_colors_organization_name_unique on public.device_colors (organization_id, lower(regexp_replace(trim(name), '\s+', ' ', 'g'))) where organization_id is not null;
insert into public.device_colors(name) select unnest(array['Negro','Blanco','Gris','Gris espacial','Plata','Titanio natural','Titanio negro','Titanio blanco','Dorado','Gold','Rose Gold','Azul','Azul oscuro','Azul marino','Celeste','Rojo','Verde','Verde oliva','Violeta','Morado','Rosa','Beige','Crema','Grafito','Carbón','Bronce','Cobre','Champagne','Midnight','Starlight','Product Red']) on conflict do nothing;
create or replace function public.create_custom_device_color(p_name text) returns setof public.device_colors language plpgsql security definer set search_path='' as $$
declare v_org uuid:=public.assert_reception_owner(); v_name text:=regexp_replace(trim(p_name),'\s+',' ','g'); v_id uuid;
begin
 if char_length(v_name) not between 2 and 80 then raise exception 'INVALID_DEVICE_COLOR'; end if;
 if exists(select 1 from public.device_colors where (organization_id is null or organization_id=v_org) and lower(regexp_replace(trim(name),'\s+',' ','g'))=lower(v_name)) then raise exception 'DEVICE_COLOR_EXISTS'; end if;
 insert into public.device_colors(organization_id,name,created_by) values(v_org,v_name,auth.uid()) returning id into v_id;
 insert into public.audit_events(organization_id,actor_user_id,event_type,entity_type,entity_id,metadata) values(v_org,auth.uid(),'DEVICE_COLOR_CREATED','DEVICE_COLOR',v_id,'{}');
 return query select * from public.device_colors where id=v_id;
end; $$;
alter table public.device_colors enable row level security;
create policy device_colors_read_owner on public.device_colors for select to authenticated using (organization_id is null or organization_id=public.current_organization_id());
grant select on public.device_colors to authenticated;
revoke all on function public.create_custom_device_color(text) from public, anon;
grant execute on function public.create_custom_device_color(text) to authenticated;
