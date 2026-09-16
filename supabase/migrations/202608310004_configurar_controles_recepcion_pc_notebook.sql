begin;

insert into public.controles_recepcion_dispositivo(clave, etiqueta, descripcion)
values
  ('estado_exterior', 'Estado exterior', 'Condición física exterior al momento del ingreso.'),
  ('encendido', 'Encendido', 'Comprobación de encendido del equipo.'),
  ('salida_video', 'Salida de video', 'Comprobación de señal de video disponible.'),
  ('puertos', 'Puertos', 'Comprobación general de puertos aplicables.'),
  ('pantalla', 'Pantalla', 'Estado funcional de la pantalla integrada.'),
  ('bateria', 'Batería', 'Estado funcional de la batería presente.'),
  ('teclado', 'Teclado', 'Estado funcional del teclado.'),
  ('touchpad', 'Touchpad', 'Estado funcional del touchpad.'),
  ('wifi', 'Conectividad Wi-Fi', 'Estado funcional de la conectividad Wi-Fi.'),
  ('unidad_optica', 'Unidad óptica', 'Estado funcional de la unidad óptica presente.'),
  ('cargador', 'Cargador recibido', 'Comprobación del cargador entregado por el cliente.')
on conflict (clave) do update
set etiqueta = excluded.etiqueta,
    descripcion = excluded.descripcion,
    activo = true,
    updated_at = now();

insert into public.tipos_dispositivo_controles_recepcion(
  fk_tipo_dispositivo_id, fk_control_recepcion_dispositivo_id, orden, obligatorio
)
select t.id, c.id, configuracion.orden, configuracion.obligatorio
from (values
  ('PC de escritorio', 'estado_exterior', 10, true),
  ('PC de escritorio', 'encendido', 20, true),
  ('PC de escritorio', 'salida_video', 30, false),
  ('PC de escritorio', 'puertos', 40, false),
  ('PC de escritorio', 'wifi', 50, false),
  ('PC de escritorio', 'unidad_optica', 60, false),
  ('Notebook', 'estado_exterior', 10, true),
  ('Notebook', 'encendido', 20, true),
  ('Notebook', 'pantalla', 30, true),
  ('Notebook', 'bateria', 40, false),
  ('Notebook', 'teclado', 50, true),
  ('Notebook', 'touchpad', 60, true),
  ('Notebook', 'wifi', 70, false),
  ('Notebook', 'unidad_optica', 80, false),
  ('Notebook', 'cargador', 90, false)
) as configuracion(tipo_nombre, control_clave, orden, obligatorio)
join public.tipos_dispositivo t
  on t.nombre_normalizado = public.normalizar_nombre_catalogo(configuracion.tipo_nombre)
join public.controles_recepcion_dispositivo c
  on c.clave = configuracion.control_clave
on conflict (fk_tipo_dispositivo_id, fk_control_recepcion_dispositivo_id)
do update set orden = excluded.orden, obligatorio = excluded.obligatorio, activo = true;

commit;
