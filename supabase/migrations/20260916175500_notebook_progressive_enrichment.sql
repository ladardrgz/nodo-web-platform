begin;

-- La recepción básica no debe depender de conocer componentes internos.
-- Si se informa una CPU/GPU/motherboard, save_customer_device_step_two valida
-- que la selección sea completa, activa y compatible.
update public.device_type_fields binding
set required = false
from public.device_types dtype, public.device_fields field
where binding.fk_tipo_dispositivo_id = dtype.id
  and binding.fk_campo_dispositivo_id = field.id
  and dtype.code = 'notebook'
  and field.key in (
    'processor_brand_id','processor_family_id','processor_generation_id',
    'processor_model_id','gpu_brand_id','gpu_family_id','gpu_model_id',
    'motherboard_brand_id','motherboard_model_id','ram_modules','storage_drives'
  );

commit;
