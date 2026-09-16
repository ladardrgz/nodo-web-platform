begin;

update public.tipos_dispositivo
set nombre = 'PC',
    updated_at = now()
where nombre_normalizado = public.normalizar_nombre_catalogo('PC de escritorio');

do $$
begin
  if (select count(*) from public.tipos_dispositivo where activo) <> 2
     or not exists (select 1 from public.tipos_dispositivo where nombre = 'PC' and activo)
     or not exists (select 1 from public.tipos_dispositivo where nombre = 'Notebook' and activo) then
    raise exception 'INVALID_CANONICAL_DEVICE_TYPES';
  end if;
end;
$$;

commit;
