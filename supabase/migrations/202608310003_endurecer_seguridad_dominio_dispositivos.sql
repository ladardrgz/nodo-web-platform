begin;

-- Las tablas operativas sólo se escriben mediante RPC con lista blanca.
revoke insert, update, delete on table
  public.dispositivos_clientes,
  public.valores_campos_dispositivo,
  public.recepciones_dispositivos,
  public.resultados_control_recepcion,
  public.fotos_recepcion,
  public.diagnosticos_dispositivo
from anon, authenticated;

drop policy if exists dispositivos_clientes_organizacion on public.dispositivos_clientes;
create policy dispositivos_clientes_lectura_organizacion
  on public.dispositivos_clientes for select to authenticated
  using (fk_organizacion_id = public.current_organization_id());

drop policy if exists recepciones_dispositivos_organizacion on public.recepciones_dispositivos;
create policy recepciones_dispositivos_lectura_organizacion
  on public.recepciones_dispositivos for select to authenticated
  using (fk_organizacion_id = public.current_organization_id());

drop policy if exists fotos_recepcion_organizacion on public.fotos_recepcion;
create policy fotos_recepcion_lectura_organizacion
  on public.fotos_recepcion for select to authenticated
  using (exists (
    select 1 from public.recepciones_dispositivos r
    where r.id = fk_recepcion_dispositivo_id
      and r.fk_organizacion_id = public.current_organization_id()
  ));

drop policy if exists diagnosticos_dispositivo_organizacion on public.diagnosticos_dispositivo;
create policy diagnosticos_dispositivo_lectura_organizacion
  on public.diagnosticos_dispositivo for select to authenticated
  using (fk_organizacion_id = public.current_organization_id());

drop policy if exists variantes_modelo_dispositivo_lectura on public.variantes_modelo_dispositivo;
create policy variantes_modelo_dispositivo_lectura
  on public.variantes_modelo_dispositivo for select to authenticated
  using (
    activo and exists (
      select 1 from public.modelos_dispositivo m
      where m.id = fk_modelo_dispositivo_id
        and m.activo
        and (m.alcance = 'GLOBAL' or m.fk_organizacion_id = public.current_organization_id())
    )
  );

drop policy if exists opciones_campo_dispositivo_lectura on public.opciones_campo_dispositivo;
create policy opciones_campo_dispositivo_lectura
  on public.opciones_campo_dispositivo for select to authenticated
  using (
    activo and exists (
      select 1 from public.campos_dispositivo c
      where c.id = fk_campo_dispositivo_id
        and c.activo
        and (c.alcance = 'GLOBAL' or c.fk_organizacion_id = public.current_organization_id())
    )
  );

drop policy if exists tipos_dispositivo_campos_lectura on public.tipos_dispositivo_campos;
create policy tipos_dispositivo_campos_lectura
  on public.tipos_dispositivo_campos for select to authenticated
  using (
    activo and exists (
      select 1 from public.campos_dispositivo c
      where c.id = fk_campo_dispositivo_id
        and c.activo
        and (c.alcance = 'GLOBAL' or c.fk_organizacion_id = public.current_organization_id())
    )
  );

create or replace function public.crear_dispositivo_cliente(
  p_cliente_id uuid,
  p_tipo_dispositivo_id uuid,
  p_marca_dispositivo_id uuid,
  p_modelo_dispositivo_id uuid default null,
  p_variante_modelo_dispositivo_id uuid default null,
  p_color_dispositivo_id uuid default null,
  p_numero_serie text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_org uuid := public.assert_reception_owner(); v_id uuid;
begin
  if not exists (select 1 from public.customers where id = p_cliente_id and organization_id = v_org) then raise exception 'INVALID_CUSTOMER'; end if;
  if not exists (select 1 from public.tipos_dispositivo where id = p_tipo_dispositivo_id and activo) then raise exception 'INVALID_DEVICE_TYPE'; end if;
  if not exists (
    select 1 from public.tipos_dispositivo_marcas tm
    join public.marcas_dispositivo m on m.id = tm.fk_marca_dispositivo_id
    where tm.fk_tipo_dispositivo_id = p_tipo_dispositivo_id
      and tm.fk_marca_dispositivo_id = p_marca_dispositivo_id
      and m.activo
      and (m.alcance = 'GLOBAL' or m.fk_organizacion_id = v_org)
  ) then raise exception 'INVALID_DEVICE_BRAND'; end if;
  if p_modelo_dispositivo_id is not null and not exists (
    select 1 from public.modelos_dispositivo m
    where m.id = p_modelo_dispositivo_id
      and m.fk_tipo_dispositivo_id = p_tipo_dispositivo_id
      and m.fk_marca_dispositivo_id = p_marca_dispositivo_id
      and m.activo
      and (m.alcance = 'GLOBAL' or m.fk_organizacion_id = v_org)
  ) then raise exception 'INVALID_DEVICE_MODEL'; end if;
  if p_variante_modelo_dispositivo_id is not null and not exists (
    select 1 from public.variantes_modelo_dispositivo v
    where v.id = p_variante_modelo_dispositivo_id
      and v.fk_modelo_dispositivo_id = p_modelo_dispositivo_id
      and v.activo
  ) then raise exception 'INVALID_DEVICE_VARIANT'; end if;
  if p_color_dispositivo_id is not null and not exists (
    select 1 from public.colores_dispositivo where id = p_color_dispositivo_id and activo
  ) then raise exception 'INVALID_DEVICE_COLOR'; end if;

  insert into public.dispositivos_clientes(
    fk_organizacion_id, fk_cliente_id, fk_tipo_dispositivo_id,
    fk_marca_dispositivo_id, fk_modelo_dispositivo_id,
    fk_variante_modelo_dispositivo_id, fk_color_dispositivo_id,
    numero_serie, created_by
  ) values (
    v_org, p_cliente_id, p_tipo_dispositivo_id,
    p_marca_dispositivo_id, p_modelo_dispositivo_id,
    p_variante_modelo_dispositivo_id, p_color_dispositivo_id,
    nullif(btrim(p_numero_serie), ''), auth.uid()
  ) returning id into v_id;

  insert into public.audit_events(organization_id, actor_user_id, event_type, entity_type, entity_id, metadata)
  values (v_org, auth.uid(), 'DISPOSITIVO_CLIENTE_CREADO', 'DISPOSITIVO_CLIENTE', v_id, '{}'::jsonb);
  return v_id;
end $$;

revoke all on function public.crear_marca_dispositivo(text, uuid) from public, anon;
revoke all on function public.crear_modelo_dispositivo(text, uuid, uuid) from public, anon;
revoke all on function public.crear_color_dispositivo(text) from public, anon, authenticated;
revoke all on function public.crear_dispositivo_cliente(uuid, uuid, uuid, uuid, uuid, uuid, text) from public, anon;
revoke all on function public.confirmar_recepcion_dispositivo(uuid, text, text, jsonb) from public, anon;

grant execute on function public.crear_marca_dispositivo(text, uuid) to authenticated;
grant execute on function public.crear_modelo_dispositivo(text, uuid, uuid) to authenticated;
grant execute on function public.crear_dispositivo_cliente(uuid, uuid, uuid, uuid, uuid, uuid, text) to authenticated;
grant execute on function public.confirmar_recepcion_dispositivo(uuid, text, text, jsonb) to authenticated;

commit;
