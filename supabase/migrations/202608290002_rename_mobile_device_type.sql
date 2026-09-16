-- Conserva el id y todas las relaciones existentes; sólo mejora el nombre visible.
update public.device_types
set name = 'Teléfono / Celular'
where organization_id is null and name = 'Celular / Smartphone';
