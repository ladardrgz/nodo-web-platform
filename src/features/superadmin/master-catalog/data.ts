import { requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { CatalogHealth, MasterCatalogData, MasterDomain, MasterOption, MasterRow } from "./types";

const supportedDomains = new Set<MasterDomain>(["general", "cpu", "gpu", "motherboard", "ram", "storage", "reception"]);

export function normalizeMasterDomain(value?: string): MasterDomain {
  return supportedDomains.has(value as MasterDomain) ? value as MasterDomain : "general";
}

export async function getMasterCatalogData(input: { deviceTypeId?: string; domain: MasterDomain; search?: string }): Promise<MasterCatalogData> {
  await requireRole(["SUPERADMIN"]);
  const supabase = await createSupabaseServerClient();
  const { data: typeRows, error: typeError } = await supabase.from("device_types").select("id,name,code,is_active").in("code", ["notebook", "desktop_pc", "cell_phone"]).eq("is_active", true).order("name");
  if (typeError || !typeRows?.length) throw new Error("No se pudieron cargar los tipos de dispositivo.");
  const deviceTypes = typeRows.map((row) => ({ id: row.id, name: row.name, code: row.code, active: row.is_active }));
  const deviceType = deviceTypes.find((row) => row.id === input.deviceTypeId) ?? deviceTypes.find((row) => row.code === "notebook") ?? deviceTypes[0];
  const { data: healthData, error: healthError } = await supabase.rpc("master_catalog_health", { p_device_type_id: deviceType.id });
  if (healthError || !healthData) throw new Error("No se pudo calcular el estado del catálogo.");

  const search = input.search?.trim() ?? "";
  let rows: MasterRow[] = [];
  const options: Record<string, MasterOption[]> = { deviceTypes };

  if (input.domain === "general") {
    const [brandsResult, modelsResult, variantsResult, colorsResult] = await Promise.all([
      supabase.from("device_type_brands").select("device_brands!inner(id,name,is_active)").eq("fk_tipo_dispositivo_id", deviceType.id).order("name", { referencedTable: "device_brands" }),
      (() => { let q = supabase.from("device_models").select("id,name,is_active,fk_marca_dispositivo_id,device_brands!inner(name)").eq("fk_tipo_dispositivo_id", deviceType.id).order("name").limit(50); if (search) q = q.ilike("name", `%${search}%`); return q; })(),
      supabase.from("device_model_variants").select("id,name,is_active,device_models!inner(name,fk_tipo_dispositivo_id,device_brands!inner(name))").eq("device_models.fk_tipo_dispositivo_id", deviceType.id).order("name").limit(50),
      supabase.from("device_colors").select("id,name,is_active").eq("alcance", "GLOBAL").order("name").limit(50),
    ]);
    const failed = [brandsResult, modelsResult, variantsResult, colorsResult].find((result) => result.error);
    if (failed?.error) throw new Error("No se pudo cargar el catálogo general.");
    const brands = (brandsResult.data ?? []).map((row) => { const brand = row.device_brands as unknown as { id: string; name: string; is_active: boolean }; return { id: brand.id, name: brand.name, active: brand.is_active }; });
    const models = (modelsResult.data ?? []).map((row) => ({ id: row.id, name: row.name, parentId: row.fk_marca_dispositivo_id, active: row.is_active }));
    options.brands = brands; options.models = models; options.colors = (colorsResult.data ?? []).map((row) => ({ id: row.id, name: row.name, active: row.is_active }));
    rows = [
      ...brands.map((item) => ({ id: item.id, entity: "device_brand", primary: item.name, secondary: "Marca", active: Boolean(item.active) })),
      ...(modelsResult.data ?? []).map((row) => ({ id: row.id, entity: "device_model", primary: row.name, secondary: (row.device_brands as unknown as { name: string }).name, tertiary: "Modelo", active: row.is_active })),
      ...(variantsResult.data ?? []).map((row) => { const model = row.device_models as unknown as { name: string; device_brands: { name: string } }; return { id: row.id, entity: "device_variant", primary: row.name, secondary: model.name, tertiary: `Variante · ${model.device_brands.name}`, active: row.is_active }; }),
      ...(colorsResult.data ?? []).map((row) => ({ id: row.id, entity: "device_color", primary: row.name, secondary: "Color global", active: row.is_active })),
    ];
  }

  if (input.domain === "cpu") {
    const [brands, families, generations, models] = await Promise.all([
      supabase.from("processor_brands").select("id,nombre,activo").order("nombre"),
      supabase.from("processor_families").select("id,nombre,activo,fk_marca_procesador_id").order("nombre"),
      supabase.from("processor_generations").select("id,name,code,is_active,fk_processor_family_id").order("sort_order"),
      (() => { let q = supabase.from("processor_models").select("id,nombre,activo,fk_familia_procesador_id,fk_processor_generation_id,processor_families!inner(nombre,processor_brands!inner(nombre)),processor_generations(name),processor_specifications!inner(notebook_supported,desktop_supported)").eq(deviceType.code === "notebook" ? "processor_specifications.notebook_supported" : "processor_specifications.desktop_supported", true).order("nombre").limit(50); if (search) q = q.ilike("nombre", `%${search}%`); return q; })(),
    ]);
    const failed = [brands, families, generations, models].find((result) => result.error); if (failed?.error) throw new Error("No se pudo cargar el catálogo CPU.");
    options.brands = (brands.data ?? []).map((x) => ({ id: x.id, name: x.nombre, active: x.activo }));
    options.families = (families.data ?? []).map((x) => ({ id: x.id, name: x.nombre, parentId: x.fk_marca_procesador_id, active: x.activo }));
    options.generations = (generations.data ?? []).map((x) => ({ id: x.id, name: x.name, code: x.code, parentId: x.fk_processor_family_id, active: x.is_active }));
    rows = (models.data ?? []).map((row) => { const family = row.processor_families as unknown as { nombre: string; processor_brands: { nombre: string } }; const spec = row.processor_specifications as unknown as { notebook_supported: boolean; desktop_supported: boolean }; return { id: row.id, entity: "processor_model", primary: row.nombre, secondary: `${family.processor_brands.nombre} · ${family.nombre}`, tertiary: (row.processor_generations as unknown as { name: string } | null)?.name ?? "Sin serie", active: row.activo, notebook: spec.notebook_supported, desktop: spec.desktop_supported }; });
  }

  if (input.domain === "gpu") {
    const [brands, families, models] = await Promise.all([
      supabase.from("gpu_brands").select("id,name,code,is_active").order("name"),
      supabase.from("gpu_families").select("id,name,code,is_active,fk_gpu_brand_id").order("name"),
      (() => { let q = supabase.from("gpu_models").select("id,name,is_active,graphics_kind,notebook_supported,desktop_supported,fk_gpu_family_id,gpu_families!inner(name,gpu_brands!inner(name))").eq(deviceType.code === "notebook" ? "notebook_supported" : "desktop_supported", true).order("name").limit(50); if (search) q = q.ilike("name", `%${search}%`); return q; })(),
    ]);
    const failed = [brands, families, models].find((result) => result.error); if (failed?.error) throw new Error("No se pudo cargar el catálogo GPU.");
    options.brands=(brands.data??[]).map(x=>({id:x.id,name:x.name,code:x.code,active:x.is_active})); options.families=(families.data??[]).map(x=>({id:x.id,name:x.name,code:x.code,parentId:x.fk_gpu_brand_id,active:x.is_active}));
    rows=(models.data??[]).map(row=>{const family=row.gpu_families as unknown as {name:string;gpu_brands:{name:string}};return{id:row.id,entity:"gpu_model",primary:row.name,secondary:`${family.gpu_brands.name} · ${family.name}`,tertiary:row.graphics_kind==="INTEGRATED"?"Integrada":"Dedicada",active:row.is_active,notebook:row.notebook_supported,desktop:row.desktop_supported};});
  }

  if (input.domain === "motherboard") {
    const [manufacturers, models] = await Promise.all([
      supabase.from("motherboard_manufacturers").select("id,name,is_active").eq("alcance","GLOBAL").order("name"),
      supabase.from("motherboard_model_device_types").select("motherboard_models!inner(id,name,is_active,motherboard_manufacturer_id,motherboard_manufacturers!inner(name))").eq("device_type_id",deviceType.id).limit(50),
    ]); const failed=[manufacturers,models].find(x=>x.error);if(failed?.error)throw new Error("No se pudo cargar el catálogo de motherboards.");
    options.manufacturers=(manufacturers.data??[]).map(x=>({id:x.id,name:x.name,active:x.is_active}));
    rows=(models.data??[]).map(row=>{const model=row.motherboard_models as unknown as {id:string;name:string;is_active:boolean;motherboard_manufacturers:{name:string}};return{id:model.id,entity:"motherboard_model",primary:model.name,secondary:model.motherboard_manufacturers.name,active:model.is_active};});
  }

  if (input.domain === "ram") {
    const [types,speeds]=await Promise.all([supabase.from("ram_types").select("id,code,name,is_active").order("name"),supabase.from("ram_speeds").select("id,mhz,is_active,fk_ram_type_id,ram_types!inner(name)").order("mhz")]);if(types.error||speeds.error)throw new Error("No se pudo cargar el catálogo RAM."); options.ramTypes=(types.data??[]).map(x=>({id:x.id,name:x.name,code:x.code,active:x.is_active})); rows=[...(types.data??[]).map(x=>({id:x.id,entity:"ram_type",primary:x.name,secondary:x.code,active:x.is_active})),...(speeds.data??[]).map(x=>({id:x.id,entity:"ram_speed",primary:`${x.mhz} MHz`,secondary:(x.ram_types as unknown as {name:string}).name,active:x.is_active}))];
  }

  if (input.domain === "storage") {
    const [interfaces,factors]=await Promise.all([supabase.from("storage_interfaces").select("id,code,name,is_active").order("name"),supabase.from("storage_form_factors").select("id,code,name,is_active").order("name")]);if(interfaces.error||factors.error)throw new Error("No se pudo cargar almacenamiento.");rows=[...(interfaces.data??[]).map(x=>({id:x.id,entity:"storage_interface",primary:x.name,secondary:`Interfaz · ${x.code}`,active:x.is_active})),...(factors.data??[]).map(x=>({id:x.id,entity:"storage_form_factor",primary:x.name,secondary:`Factor · ${x.code}`,active:x.is_active}))];
  }

  if (input.domain === "reception") {
    const {data,error}=await supabase.from("device_type_reception_controls").select("sort_order,obligatorio,is_active,device_reception_controls!inner(id,key,label,is_active,is_critical)").eq("fk_tipo_dispositivo_id",deviceType.id).order("sort_order");if(error)throw new Error("No se pudo cargar el checklist.");rows=(data??[]).map(row=>{const control=row.device_reception_controls as unknown as {id:string;key:string;label:string;is_active:boolean;is_critical:boolean};return{id:control.id,entity:"reception_control",primary:control.label,secondary:control.key,tertiary:control.is_critical?"Crítico":"Opcional",active:row.is_active&&control.is_active};});
  }

  return { domain: input.domain, deviceType, deviceTypes, health: healthData as unknown as CatalogHealth, rows, options };
}
