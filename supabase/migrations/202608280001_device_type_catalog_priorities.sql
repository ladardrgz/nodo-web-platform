-- Amplía el catálogo global de dispositivos sin modificar recepciones históricas.
-- Los tipos siguen siendo relacionales: customer_devices.type_id conserva la categoría y
-- customer_devices.attributes guarda sólo los campos aplicables al grupo seleccionado.

create index if not exists customer_devices_organization_type_idx
  on public.customer_devices (organization_id, type_id);

-- Las opciones genéricas se reemplazan por familias identificables. No se eliminan para
-- preservar dispositivos y recepciones existentes; sólo dejan de ofrecerse para nuevas altas.
update public.device_types
set is_active = false
where organization_id is null
  and name in ('Consola de videojuegos', 'Consola portátil');

insert into public.device_types (name, category, attribute_group)
values
  ('PlayStation 1', 'Consolas y gaming', 'GAMING'),
  ('PlayStation 2', 'Consolas y gaming', 'GAMING'),
  ('PlayStation 3', 'Consolas y gaming', 'GAMING'),
  ('PlayStation 4', 'Consolas y gaming', 'GAMING'),
  ('PlayStation 5', 'Consolas y gaming', 'GAMING'),
  ('PSP', 'Consolas y gaming', 'GAMING'),
  ('PlayStation Vita', 'Consolas y gaming', 'GAMING'),
  ('Xbox clásica', 'Consolas y gaming', 'GAMING'),
  ('Xbox 360', 'Consolas y gaming', 'GAMING'),
  ('Xbox One', 'Consolas y gaming', 'GAMING'),
  ('Xbox Series S/X', 'Consolas y gaming', 'GAMING'),
  ('Nintendo NES', 'Consolas y gaming', 'GAMING'),
  ('Super Nintendo', 'Consolas y gaming', 'GAMING'),
  ('Nintendo 64', 'Consolas y gaming', 'GAMING'),
  ('Nintendo GameCube', 'Consolas y gaming', 'GAMING'),
  ('Nintendo Wii', 'Consolas y gaming', 'GAMING'),
  ('Nintendo Wii U', 'Consolas y gaming', 'GAMING'),
  ('Nintendo Switch', 'Consolas y gaming', 'GAMING'),
  ('Nintendo Switch Lite', 'Consolas y gaming', 'GAMING'),
  ('Nintendo DS / 3DS', 'Consolas y gaming', 'GAMING'),
  ('Steam Deck', 'Consolas y gaming', 'GAMING'),
  ('Joystick / Gamepad', 'Consolas y gaming', 'PERIPHERAL'),
  ('Volante gaming', 'Consolas y gaming', 'PERIPHERAL'),
  ('Visor VR', 'Consolas y gaming', 'GAMING'),
  ('Otra consola', 'Consolas y gaming', 'GAMING')
on conflict do nothing;

comment on index public.customer_devices_organization_type_idx is
  'Acelera consultas de tipos de equipo por organización.';
