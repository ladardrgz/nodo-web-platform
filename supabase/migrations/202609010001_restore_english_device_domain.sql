-- Restore the device domain to the canonical English naming convention.
-- This migration is intentionally incremental: the previous migrations are
-- already recorded remotely, so replacing their history would make the linked
-- Supabase project unrecoverable. All catalog cleanup happens in this single
-- transaction and excludes Supabase-managed schemas.
begin;

-- Remove the development-only catalog data in dependency order. Customer and
-- reception history is removed as explicitly authorized for this development
-- project; the tables themselves and their RLS policies are retained.
truncate table
  public.fotos_recepcion,
  public.resultados_control_recepcion,
  public.recepciones_dispositivos,
  public.valores_campos_dispositivo,
  public.dispositivos_clientes_accesorios,
  public.almacenamientos_dispositivo,
  public.memoria_ram_dispositivo,
  public.procesadores_dispositivos,
  public.dispositivos_clientes,
  public.dependencias_campo_dispositivo,
  public.tipos_dispositivo_campos,
  public.opciones_campo_dispositivo,
  public.campos_dispositivo,
  public.secciones_formulario_dispositivo,
  public.tipos_dispositivo_controles_recepcion,
  public.controles_recepcion_dispositivo,
  public.variantes_modelo_dispositivo,
  public.modelos_dispositivo,
  public.tipos_dispositivo_marcas,
  public.marcas_dispositivo,
  public.colores_dispositivo,
  public.tipos_dispositivo,
  public.modelos_procesador,
  public.familias_procesador,
  public.marcas_procesador,
  public.modelos_componente,
  public.categorias_componente_marcas,
  public.marcas_componente,
  public.categorias_componente,
  public.tipos_almacenamiento,
  public.accesorios_dispositivo
restart identity cascade;

-- Canonical table names. Foreign-key columns in this domain already use the
-- fk_ prefix; table renames preserve constraints, indexes, RLS and ownership.
alter table public.tipos_dispositivo rename to device_types;
alter table public.marcas_dispositivo rename to device_brands;
alter table public.tipos_dispositivo_marcas rename to device_type_brands;
alter table public.modelos_dispositivo rename to device_models;
alter table public.variantes_modelo_dispositivo rename to device_model_variants;
alter table public.colores_dispositivo rename to device_colors;
alter table public.dispositivos_clientes rename to customer_devices;
alter table public.secciones_formulario_dispositivo rename to device_form_sections;
alter table public.campos_dispositivo rename to device_fields;
alter table public.opciones_campo_dispositivo rename to device_field_options;
alter table public.tipos_dispositivo_campos rename to device_type_fields;
alter table public.valores_campos_dispositivo rename to customer_device_field_values;
alter table public.dependencias_campo_dispositivo rename to device_field_dependencies;
alter table public.controles_recepcion_dispositivo rename to device_reception_controls;
alter table public.tipos_dispositivo_controles_recepcion rename to device_type_reception_controls;
alter table public.recepciones_dispositivos rename to device_receptions;
alter table public.resultados_control_recepcion rename to reception_inspection_items;
alter table public.fotos_recepcion rename to reception_photos;
alter table public.diagnosticos_dispositivo rename to device_diagnostics;
alter table public.marcas_procesador rename to processor_brands;
alter table public.familias_procesador rename to processor_families;
alter table public.modelos_procesador rename to processor_models;
alter table public.procesadores_dispositivos rename to customer_device_processors;
alter table public.categorias_componente rename to component_categories;
alter table public.marcas_componente rename to component_brands;
alter table public.categorias_componente_marcas rename to component_category_brands;
alter table public.modelos_componente rename to component_models;
alter table public.memoria_ram_dispositivo rename to customer_device_memory_modules;
alter table public.tipos_almacenamiento rename to storage_types;
alter table public.almacenamientos_dispositivo rename to customer_device_storage_units;
alter table public.accesorios_dispositivo rename to device_accessories;
alter table public.dispositivos_clientes_accesorios rename to customer_device_accessories;

-- Translate non-key columns used by the application contract.
alter table public.device_types rename column nombre to name;
alter table public.device_types rename column nombre_normalizado to normalized_name;
alter table public.device_types rename column activo to is_active;
alter table public.device_brands rename column nombre to name;
alter table public.device_brands rename column nombre_normalizado to normalized_name;
alter table public.device_brands rename column activo to is_active;
alter table public.device_models rename column nombre to name;
alter table public.device_models rename column nombre_normalizado to normalized_name;
alter table public.device_models rename column activo to is_active;
alter table public.device_model_variants rename column nombre to name;
alter table public.device_model_variants rename column nombre_normalizado to normalized_name;
alter table public.device_model_variants rename column activo to is_active;
alter table public.device_colors rename column nombre to name;
alter table public.device_colors rename column nombre_normalizado to normalized_name;
alter table public.device_colors rename column activo to is_active;
alter table public.device_form_sections rename column clave to key;
alter table public.device_form_sections rename column titulo to title;
alter table public.device_form_sections rename column descripcion to description;
alter table public.device_form_sections rename column orden to sort_order;
alter table public.device_form_sections rename column activo to is_active;
alter table public.device_fields rename column clave to key;
alter table public.device_fields rename column etiqueta to label;
alter table public.device_fields rename column tipo_campo to field_type;
alter table public.device_fields rename column clave_fuente_datos to data_source_key;
alter table public.device_fields rename column texto_ayuda to help_text;
alter table public.device_fields rename column validacion to validation;
alter table public.device_fields rename column activo to is_active;
alter table public.device_field_options rename column valor to value;
alter table public.device_field_options rename column etiqueta to label;
alter table public.device_field_options rename column orden to sort_order;
alter table public.device_field_options rename column activo to is_active;
alter table public.device_type_fields rename column orden to sort_order;
alter table public.device_type_fields rename column obligatorio to required;
alter table public.device_type_fields rename column activo to is_active;
alter table public.device_reception_controls rename column clave to key;
alter table public.device_reception_controls rename column etiqueta to label;
alter table public.device_reception_controls rename column es_critico to is_critical;
alter table public.device_reception_controls rename column activo to is_active;
alter table public.device_type_reception_controls rename column orden to sort_order;
alter table public.device_type_reception_controls rename column activo to is_active;
alter table public.device_receptions rename column problema_informado to reported_problem;
alter table public.device_receptions rename column observaciones to observations;
alter table public.device_receptions rename column puntaje_condicion to condition_score;
alter table public.device_receptions rename column condicion_calculada to calculated_condition;
alter table public.device_receptions rename column estado to status;
alter table public.reception_inspection_items rename column condicion to condition;
alter table public.reception_inspection_items rename column observacion to observation;
alter table public.reception_inspection_items rename column es_critico to is_critical;
alter table public.reception_photos rename column ruta_storage to storage_path;
alter table public.reception_photos rename column descripcion to description;
alter table public.reception_photos rename column clave_control to inspection_key;

-- The only canonical types left after the catalog reset.
insert into public.device_types (name, is_active)
values ('Desktop PC', true), ('Notebook', true);

-- Catalogs are read-only from the browser. Writes remain restricted to the
-- existing SECURITY DEFINER RPCs, which derive the organization from auth.uid.
revoke insert, update, delete on table
  public.device_types, public.device_brands, public.device_type_brands,
  public.device_models, public.device_model_variants, public.device_colors,
  public.device_form_sections, public.device_fields, public.device_field_options,
  public.device_type_fields, public.device_reception_controls,
  public.device_type_reception_controls
from anon, authenticated;

commit;
