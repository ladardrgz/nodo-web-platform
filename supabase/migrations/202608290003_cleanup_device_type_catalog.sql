-- El catálogo de tipos describe categorías de equipos, no modelos o variantes.
-- Se desactivan sólo opciones redundantes: los dispositivos históricos conservan sus relaciones.
update public.device_types
set is_active = false
where organization_id is null and name in (
  'iPad','Smartband','Ultrabook','Netbook','Chromebook','MacBook','PC gamer','Workstation',
  'Fuente ATX','Disco externo','SSD externo','Pendrive','Smart TV','TV LED/LCD','Cámara IP',
  'Impresora láser','Impresora tinta','Impresora multifunción','Impresora de etiquetas',
  'PlayStation 1','PlayStation 2','PlayStation 3','PlayStation 4','PlayStation 5','PSP','PlayStation Vita',
  'Xbox clásica','Xbox 360','Xbox One','Xbox Series S/X','Nintendo NES','Super Nintendo','Nintendo 64',
  'Nintendo GameCube','Nintendo Wii','Nintendo Wii U','Nintendo Switch','Nintendo Switch Lite',
  'Nintendo DS / 3DS','Steam Deck','Otra consola'
);

update public.device_types set is_active = true
where organization_id is null and name in ('Consola de videojuegos','Consola portátil');

update public.device_types set name = 'Teléfono / Celular'
where organization_id is null and name = 'Celular / Smartphone';

insert into public.device_types(name, category, attribute_group) values
  ('Notebook / Laptop','Computación','COMPUTER'), ('GPU / Placa de vídeo','Componentes','OTHER'),
  ('Almacenamiento externo','Componentes','STORAGE'), ('Televisor / Smart TV','Imagen y visualización','DISPLAY'),
  ('Cámara de seguridad','Imagen y visualización','CAMERA'), ('Impresora','Impresión','PRINTER'), ('Plotter','Impresión','PRINTER')
on conflict do nothing;
