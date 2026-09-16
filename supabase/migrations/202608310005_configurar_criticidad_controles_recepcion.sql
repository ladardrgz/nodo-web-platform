begin;

alter table public.controles_recepcion_dispositivo
  add column es_critico boolean not null default false;

update public.controles_recepcion_dispositivo
set es_critico = clave in ('encendido', 'pantalla', 'bateria');

commit;
