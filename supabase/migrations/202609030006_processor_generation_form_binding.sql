-- Data-only completion of the existing dynamic form contract. No tables or
-- columns are created: processor_generations and its FK already exist.
begin;

alter table public.device_fields drop constraint if exists device_fields_data_source_key_check;
alter table public.device_fields add constraint device_fields_data_source_key_check check (data_source_key is null or data_source_key in (
  'brand','family','model','variant','color','memory_capacity','storage_capacity','storage_type','operating_system','mobile_operator','accessory','lock_type','notebook_keyboard_mount',
  'hardware_processor_brand','hardware_processor_family','hardware_processor_generation','hardware_processor_model',
  'hardware_motherboard_brand','hardware_motherboard_model','hardware_gpu_brand','hardware_gpu_model','hardware_power_supply_brand','hardware_power_supply_model','hardware_case_brand','hardware_case_model','hardware_cpu_cooler_brand','hardware_cpu_cooler_model','hardware_wifi_brand','hardware_wifi_model'
));

insert into public.device_fields(key,label,field_type,data_source_key,placeholder,alcance,is_active)
values ('processor_generation_id','Generación / Serie','SELECT','hardware_processor_generation','Primero seleccioná la familia','GLOBAL',true)
on conflict (key,fk_organizacion_id) do update set label=excluded.label,field_type=excluded.field_type,data_source_key=excluded.data_source_key,placeholder=excluded.placeholder,is_active=true;

insert into public.device_type_fields(fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,sort_order,required,is_active)
select t.id,s.id,f.id,25,false,true
from public.device_types t
join public.device_form_sections s on s.key=case when t.code='desktop_pc' then 'pc_processor' else 'notebook_processor' end and s.alcance='GLOBAL'
join public.device_fields f on f.key='processor_generation_id' and f.alcance='GLOBAL'
where t.code in ('desktop_pc','notebook')
on conflict (fk_tipo_dispositivo_id,fk_campo_dispositivo_id) do update set fk_seccion_formulario_dispositivo_id=excluded.fk_seccion_formulario_dispositivo_id,sort_order=excluded.sort_order,required=excluded.required,is_active=true;

commit;
