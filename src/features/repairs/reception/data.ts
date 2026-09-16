import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import type {
  CatalogOption,
  DeviceColorOption,
  DynamicDeviceSection,
  ReceptionControl,
  ReceptionFormData,
} from "./types";

interface FieldBinding {
  id: string;
  fk_tipo_dispositivo_id: string;
  fk_seccion_formulario_dispositivo_id: string;
  sort_order: number;
  required: boolean;
  overrides: DynamicDeviceSection["fields"][number]["overrides"];
  fk_campo_dispositivo_id: string;
  device_fields: {
    key: string;
    label: string;
    field_type: DynamicDeviceSection["fields"][number]["fieldType"];
    data_source_key: DynamicDeviceSection["fields"][number]["dataSourceKey"];
    placeholder: string | null;
    help_text: string | null;
    validation: DynamicDeviceSection["fields"][number]["validation"];
  } | null;
}

interface FieldDependency {
  fk_tipo_dispositivo_campo_id: string;
  fk_tipo_dispositivo_campo_padre_id: string;
  operator: "EQUALS" | "NOT_EQUALS" | "IN" | "NOT_EMPTY" | "EMPTY";
  expected_value: unknown;
}

export async function getReceptionFormData(
  organizationId: string,
): Promise<ReceptionFormData> {
  const supabase = await createSupabaseServerClient();
  const [
    customers,
    types,
    colors,
    sections,
    bindings,
    options,
    dependencies,
    controls,
    controlBindings,
    componentCategories,
    componentBrands,
    componentBrandCategories,
    componentModels,
    storageTypes,
    accessories,
  ] = await Promise.all([
    supabase
      .from("customers")
      .select("id,first_name,last_name,phone,contact_email")
      .eq("organization_id", organizationId)
      .order("last_name"),
    supabase
      .from("device_types")
      .select("id,name,code")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("device_colors")
      .select("id,name,fk_organizacion_id")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("device_form_sections")
      .select("id,key,title,description,sort_order,ui_config,is_active")
      .eq("is_active", true)
      .order("sort_order"),
    supabase
      .from("device_type_fields")
      .select(
        "id,fk_tipo_dispositivo_id,fk_seccion_formulario_dispositivo_id,fk_campo_dispositivo_id,sort_order,required,overrides,device_fields!inner(key,label,field_type,data_source_key,placeholder,help_text,validation)",
      )
      .eq("is_active", true)
      .order("sort_order"),
    supabase
      .from("device_field_options")
      .select("id,fk_campo_dispositivo_id,value,label,sort_order")
      .eq("is_active", true)
      .order("sort_order"),
    supabase
      .from("device_field_dependencies")
      .select(
        "fk_tipo_dispositivo_campo_id,fk_tipo_dispositivo_campo_padre_id,operator,expected_value",
      ),
    supabase
      .from("device_reception_controls")
      .select("id,key,label,is_critical")
      .eq("is_active", true),
    supabase
      .from("device_type_reception_controls")
      .select(
        "fk_tipo_dispositivo_id,fk_control_recepcion_dispositivo_id,sort_order",
      )
      .eq("is_active", true)
      .order("sort_order"),
    supabase.from("component_categories").select("id,clave").eq("activo", true),
    supabase
      .from("component_brands")
      .select("id,nombre,fk_organizacion_id")
      .eq("activo", true)
      .order("nombre"),
    supabase
      .from("component_category_brands")
      .select("fk_categoria_componente_id,fk_marca_componente_id"),
    supabase
      .from("component_models")
      .select(
        "id,nombre,fk_categoria_componente_id,fk_marca_componente_id,fk_organizacion_id",
      )
      .eq("activo", true)
      .order("nombre"),
    supabase
      .from("storage_types")
      .select("id,nombre,fk_organizacion_id")
      .eq("activo", true)
      .order("nombre"),
    supabase
      .from("device_accessories")
      .select("id,nombre,fk_organizacion_id")
      .eq("activo", true)
      .order("nombre"),
  ]);
  if (
    [
      customers,
      types,
      colors,
      sections,
      bindings,
      options,
      dependencies,
      controls,
      controlBindings,
      componentCategories,
      componentBrands,
      componentBrandCategories,
      componentModels,
      storageTypes,
      accessories,
    ].some((result) => result.error)
  )
    throw new Error("RECEPTION_SCHEMA_UNAVAILABLE");
  const [
    ramTypes,
    ramSpeeds,
    ramFormFactors,
    storageInterfaces,
    storageFormFactors,
    storageCapacities,
    operatingSystems,
    legacyHardware,
  ] = await Promise.all([
    supabase
      .from("ram_types")
      .select("id,code,name")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("ram_speeds")
      .select("id,fk_ram_type_id,mhz")
      .eq("is_active", true)
      .order("mhz"),
    supabase
      .from("ram_form_factors")
      .select("id,code,name")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("storage_interfaces")
      .select("id,code,name")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("storage_form_factors")
      .select("id,code,name")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("storage_capacities")
      .select("id,capacity_gb,label")
      .eq("is_active", true)
      .order("capacity_gb"),
    supabase
      .from("operating_systems")
      .select("id,code,name,organization_id")
      .eq("is_active", true)
      .order("name"),
    supabase
      .from("hardware_catalog_items")
      .select("id,category,code,name,parent_id")
      .eq("is_active", true)
      .order("name"),
  ]);
  if (
    [
      ramTypes,
      ramSpeeds,
      ramFormFactors,
      storageInterfaces,
      storageFormFactors,
      storageCapacities,
      operatingSystems,
      legacyHardware,
    ].some((result) => result.error)
  )
    throw new Error("RECEPTION_TECHNICAL_CATALOGS_UNAVAILABLE");

  const optionsByField = new Map<
    string,
    Array<{ id: string; value: string; label: string }>
  >();
  for (const option of options.data ?? [])
    optionsByField.set(option.fk_campo_dispositivo_id, [
      ...(optionsByField.get(option.fk_campo_dispositivo_id) ?? []),
      option,
    ]);
  const sectionsById = new Map(
    (sections.data ?? []).map((section) => [section.id, section]),
  );
  const dependenciesByBinding = new Map<string, FieldDependency[]>();
  for (const dependency of (dependencies.data ?? []) as FieldDependency[])
    dependenciesByBinding.set(dependency.fk_tipo_dispositivo_campo_id, [
      ...(dependenciesByBinding.get(dependency.fk_tipo_dispositivo_campo_id) ??
        []),
      dependency,
    ]);
  const formSectionsByType: Record<string, DynamicDeviceSection[]> = {};
  for (const binding of (bindings.data ?? []) as unknown as FieldBinding[]) {
    const section = sectionsById.get(
      binding.fk_seccion_formulario_dispositivo_id,
    );
    if (!section || !binding.device_fields) continue;
    const target = (formSectionsByType[binding.fk_tipo_dispositivo_id] ??= []);
    let result = target.find((item) => item.id === section.id);
    if (!result) {
      result = {
        id: section.id,
        key: section.key,
        title: section.title,
        description: section.description,
        sortOrder: section.sort_order,
        uiConfig: section.ui_config ?? {},
        fields: [],
      };
      target.push(result);
    }
    const field = binding.device_fields;
    result.fields.push({
      bindingId: binding.id,
      key: field.key,
      label: field.label,
      fieldType: field.field_type,
      dataSourceKey: field.data_source_key,
      placeholder: field.placeholder,
      helpText: field.help_text,
      validation: field.validation ?? {},
      required: binding.required,
      overrides: binding.overrides ?? {},
      options: (optionsByField.get(binding.fk_campo_dispositivo_id) ?? []).map(
        (option) => ({
          id: option.id,
          value: option.value,
          label: option.label,
        }),
      ),
      dependencies: (dependenciesByBinding.get(binding.id) ?? []).map(
        (dependency) => ({
          parentBindingId: dependency.fk_tipo_dispositivo_campo_padre_id,
          operator: dependency.operator,
          expectedValue: dependency.expected_value,
        }),
      ),
    });
  }
  for (const typeSections of Object.values(formSectionsByType))
    typeSections.sort((left, right) => left.sortOrder - right.sortOrder);
  const controlsById = new Map(
    (controls.data ?? []).map((control) => [control.id, control]),
  );
  const receptionControlsByType: Record<string, ReceptionControl[]> = {};
  for (const binding of controlBindings.data ?? []) {
    const control = controlsById.get(
      binding.fk_control_recepcion_dispositivo_id,
    );
    if (control)
      (receptionControlsByType[binding.fk_tipo_dispositivo_id] ??= []).push({
        key: control.key,
        label: control.label,
        applicableWhenAttribute: null,
        critical: control.is_critical,
      });
  }
  return {
    customers: (customers.data ?? []).map((row) => ({
      id: row.id,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      email: row.contact_email ?? "",
    })),
    deviceTypes: (types.data ?? []).map(
      (row) =>
        ({
          id: row.id,
          name: row.name,
          code: row.code,
          organizationId: null,
        }) satisfies CatalogOption,
    ),
    brands: [],
    deviceModels: [],
    deviceColors: (colors.data ?? []).map(
      (row) =>
        ({
          id: row.id,
          name: row.name,
          organizationId: row.fk_organizacion_id,
        }) satisfies DeviceColorOption,
    ),
    // Las variantes son dependientes del modelo y se solicitan bajo demanda.
    deviceVariants: [],
    formSectionsByType,
    receptionControlsByType,
    fieldCatalogs: (() => {
      const catalog: Record<string, CatalogOption[]> = {
        color: (colors.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          organizationId: row.fk_organizacion_id,
        })),
        hardware_processor_brand: [],
        hardware_processor_family: [],
        hardware_processor_generation: [],
        hardware_processor_model: [],
        storage_type: (storageTypes.data ?? []).map((row) => ({
          id: row.id,
          name: row.nombre,
          organizationId: row.fk_organizacion_id,
        })),
        ram_type: (ramTypes.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          code: row.code,
          organizationId: null,
        })),
        ram_speed: (ramSpeeds.data ?? []).map((row) => ({
          id: row.id,
          name: `${row.mhz} MHz`,
          parentId: row.fk_ram_type_id,
          organizationId: null,
        })),
        ram_form_factor: (ramFormFactors.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          code: row.code,
          organizationId: null,
        })),
        storage_interface: (storageInterfaces.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          code: row.code,
          organizationId: null,
        })),
        storage_form_factor: (storageFormFactors.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          code: row.code,
          organizationId: null,
        })),
        storage_capacity: (storageCapacities.data ?? []).map((row) => ({
          id: row.id,
          name: row.label,
          code: String(row.capacity_gb),
          organizationId: null,
        })),
        operating_system: (operatingSystems.data ?? []).map((row) => ({
          id: row.id,
          name: row.name,
          code: row.code ?? undefined,
          organizationId: row.organization_id,
        })),
        accessory: (accessories.data ?? []).map((row) => ({
          id: row.id,
          name: row.nombre,
          organizationId: row.fk_organizacion_id,
        })),
        gpu_brands: [],
        gpu_families: [],
        gpu_models: [],
      };
      for (const item of legacyHardware.data ?? []) {
        const key = `legacy_${item.category.toLowerCase()}`;
        (catalog[key] ??= []).push({
          id: item.id,
          name: item.name,
          code: item.code,
          parentId: item.parent_id,
          organizationId: null,
        });
      }
      const sourceByCategory: Record<string, [string, string]> = {
        GABINETE: ["hardware_case_brand", "hardware_case_model"],
        FUENTE_ALIMENTACION: [
          "hardware_power_supply_brand",
          "hardware_power_supply_model",
        ],
        PLACA_MADRE: [
          "hardware_motherboard_brand",
          "hardware_motherboard_model",
        ],
        TARJETA_GRAFICA: ["hardware_gpu_brand", "hardware_gpu_model"],
        COOLER_PROCESADOR: [
          "hardware_cpu_cooler_brand",
          "hardware_cpu_cooler_model",
        ],
        ADAPTADOR_WIFI: ["hardware_wifi_brand", "hardware_wifi_model"],
      };
      for (const category of componentCategories.data ?? []) {
        const sources = sourceByCategory[category.clave];
        if (!sources) continue;
        const brandIds = new Set(
          (componentBrandCategories.data ?? [])
            .filter((row) => row.fk_categoria_componente_id === category.id)
            .map((row) => row.fk_marca_componente_id),
        );
        catalog[sources[0]] = (componentBrands.data ?? [])
          .filter((row) => brandIds.has(row.id))
          .map((row) => ({
            id: row.id,
            name: row.nombre,
            organizationId: row.fk_organizacion_id,
          }));
        catalog[sources[1]] = (componentModels.data ?? [])
          .filter((row) => row.fk_categoria_componente_id === category.id)
          .map((row) => ({
            id: row.id,
            name: row.nombre,
            parentId: row.fk_marca_componente_id,
            organizationId: row.fk_organizacion_id,
          }));
      }
      return catalog;
    })(),
    accessories: (accessories.data ?? []).map((row) => ({
      id: row.id,
      name: row.nombre,
      organizationId: row.fk_organizacion_id,
    })),
    suggestions: { models: [] },
  };
}
