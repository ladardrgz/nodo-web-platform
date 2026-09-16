-- Optional serial numbers must still identify a single physical device inside
-- an organization. Existing data was audited for collisions before this index.
create unique index uq_customer_devices_organization_serial_number
  on public.customer_devices (fk_organizacion_id, lower(numero_serie))
  where numero_serie is not null;

-- Notebook intake requires verified identity plus the technical minimum chosen
-- by operations. All other technical/reception details remain optional.
update public.device_type_fields binding
set required = true
from public.device_types type, public.device_fields field
where binding.fk_tipo_dispositivo_id = type.id
  and binding.fk_campo_dispositivo_id = field.id
  and type.code = 'notebook'
  and field.key in (
    'processor_brand_id', 'processor_family_id', 'processor_generation_id',
    'processor_model_id', 'ram_modules', 'storage_drives', 'operating_system_id'
  );
