begin;

-- La FK compuesta protege la coherencia tipo-marca, pero PostgREST necesita
-- además una relación directa para resolver el embed marcas_dispositivo(...).
alter table public.dispositivos_clientes
  add constraint fk_dispositivos_clientes_marca_dispositivo
  foreign key (fk_marca_dispositivo_id)
  references public.marcas_dispositivo(id)
  on delete restrict;

create index ix_dispositivos_clientes_marca_dispositivo
  on public.dispositivos_clientes(fk_marca_dispositivo_id);

create or replace function public.registrar_foto_recepcion(
  p_recepcion_dispositivo_id uuid,
  p_ruta_storage text,
  p_descripcion text default null,
  p_clave_control text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.registrar_foto_recepcion(uuid, text, text, text) from public, anon;
grant execute on function public.registrar_foto_recepcion(uuid, text, text, text) to authenticated;

commit;
