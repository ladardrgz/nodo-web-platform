-- Restore the editable, database-driven intake forms for the two canonical types.
begin;

-- OEM brands are deliberately associated to a type; component makers remain in
-- component_brands and never leak into the equipment-brand selector.
insert into public.device_brands(name, alcance, fk_organizacion_id, is_active)
select v.name, 'GLOBAL', null, true from (values
 ('Acer'),('Alienware'),('ASUS'),('Dell'),('HP'),('Lenovo'),('MSI'),('Apple'),('Samsung'),('Ensamblada / Custom')
) v(name) on conflict (normalized_name, fk_organizacion_id) do update set is_active=true;

insert into public.device_type_brands(fk_tipo_dispositivo_id,fk_marca_dispositivo_id)
select t.id,b.id from public.device_types t join public.device_brands b on b.name = any(
 case when t.code='desktop_pc' then array['Acer','Alienware','ASUS','Dell','HP','Lenovo','MSI','Ensamblada / Custom'] else array['Acer','Apple','ASUS','Dell','HP','Lenovo','MSI','Samsung'] end)
where t.code in ('desktop_pc','notebook') on conflict do nothing;

insert into public.device_form_sections(key,title,description,alcance,fk_organizacion_id,is_active)
values
 ('pc_identification','Identificación','Datos visibles al recibir el equipo.','GLOBAL',null,true),
 ('pc_processor','Procesador','Selección dependiente desde el catálogo técnico.','GLOBAL',null,true),
 ('pc_hardware','Hardware','Componentes conocidos durante la recepción.','GLOBAL',null,true),
 ('pc_software','Sistema operativo y conectividad','Datos disponibles al ingreso.','GLOBAL',null,true),
 ('notebook_identification','Identificación','Datos visibles al recibir la notebook.','GLOBAL',null,true),
 ('notebook_display','Pantalla y alimentación','Información de pantalla, batería y cargador.','GLOBAL',null,true),
 ('notebook_processor','Procesador','Selección dependiente desde el catálogo técnico.','GLOBAL',null,true),
 ('notebook_hardware','Hardware y conectividad','RAM, almacenamiento, puertos y conectividad.','GLOBAL',null,true)
on conflict (key,fk_organizacion_id) do update set title=excluded.title,description=excluded.description,is_active=true;

insert into public.device_fields(key,label,field_type,data_source_key,placeholder,alcance,is_active)
values
 ('equipment_kind','Tipo de equipo','RADIO',null,null,'GLOBAL',true),
 ('service_tag','Service Tag / Product Number','TEXT',null,'Opcional','GLOBAL',true),
 ('processor_brand_id','Fabricante CPU','SELECT','hardware_processor_brand','Seleccionar fabricante','GLOBAL',true),
 ('processor_family_id','Familia CPU','SELECT','hardware_processor_family','Seleccionar familia','GLOBAL',true),
 ('processor_model_id','Modelo CPU','SELECT','hardware_processor_model','Seleccionar modelo','GLOBAL',true),
 ('motherboard_brand_id','Fabricante motherboard','SELECT','hardware_motherboard_brand','Seleccionar fabricante','GLOBAL',true),
 ('motherboard_model_id','Modelo motherboard','SELECT','hardware_motherboard_model','Seleccionar modelo','GLOBAL',true),
 ('gpu_brand_id','Fabricante GPU','SELECT','hardware_gpu_brand','Seleccionar fabricante','GLOBAL',true),
 ('gpu_model_id','Modelo GPU','SELECT','hardware_gpu_model','Seleccionar modelo','GLOBAL',true),
 ('screen_size','Tamaño de pantalla','TEXT',null,'Ej. 15.6 pulgadas','GLOBAL',true),
 ('screen_resolution','Resolución','TEXT',null,'Ej. 1920×1080','GLOBAL',true),
 ('battery_status','Estado de batería','TEXT',null,'Presente, no comprobada, dañada…','GLOBAL',true),
 ('charger_status','Estado de cargador','TEXT',null,'Entregado, original, alternativo…','GLOBAL',true)
on conflict (key,fk_organizacion_id) do update set label=excluded.label,field_type=excluded.field_type,data_source_key=excluded.data_source_key,is_active=true;

insert into public.device_field_options(fk_campo_dispositivo_id,value,label,sort_order,is_active)
select f.id,v.value,v.label,v.sort_order,true from public.device_fields f join (values
 ('equipment_kind','OEM','Equipo de marca / OEM',10),('equipment_kind','CUSTOM','PC ensamblada',20)
) v(field_key,value,label,sort_order) on f.key=v.field_key
on conflict (fk_campo_dispositivo_id,value) do update set label=excluded.label,is_active=true;

with bindings(type_code,section_key,field_key,sort_order,required) as (values
 ('desktop_pc','pc_identification','equipment_kind',10,true),('desktop_pc','pc_processor','processor_brand_id',10,false),('desktop_pc','pc_processor','processor_family_id',20,false),('desktop_pc','pc_processor','processor_model_id',30,false),('desktop_pc','pc_hardware','motherboard_brand_id',10,false),('desktop_pc','pc_hardware','motherboard_model_id',20,false),('desktop_pc','pc_hardware','gpu_brand_id',30,false),('desktop_pc','pc_hardware','gpu_model_id',40,false),
 ('notebook','notebook_identification','service_tag',10,false),('notebook','notebook_display','screen_size',10,false),('notebook','notebook_display','screen_resolution',20,false),('notebook','notebook_display','battery_status',30,false),('notebook','notebook_display','charger_status',40,false),('notebook','notebook_processor','processor_brand_id',10,false),('notebook','notebook_processor','processor_family_id',20,false),('notebook','notebook_processor','processor_model_id',30,false)
)
insert into public.device_type_fields(fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,sort_order,required,is_active)
select t.id,s.id,f.id,b.sort_order,b.required,true from bindings b join public.device_types t on t.code=b.type_code join public.device_form_sections s on s.key=b.section_key and s.alcance='GLOBAL' join public.device_fields f on f.key=b.field_key and f.alcance='GLOBAL'
on conflict (fk_tipo_dispositivo_id,fk_campo_dispositivo_id) do update set fk_seccion_formulario_dispositivo_id=excluded.fk_seccion_formulario_dispositivo_id,sort_order=excluded.sort_order,required=excluded.required,is_active=true;

commit;
