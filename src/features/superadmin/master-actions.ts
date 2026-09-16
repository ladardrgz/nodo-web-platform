"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const uuid = z.string().uuid();
const name = z.string().trim().min(2).max(200);
const createSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("device_brand"), name: name.max(80), deviceTypeIds: z.array(uuid).min(1) }),
  z.object({ kind: z.literal("device_model"), name: name.max(120), deviceTypeId: uuid, brandId: uuid }),
  z.object({ kind: z.literal("device_variant"), name: name.max(140), modelId: uuid }),
  z.object({ kind: z.literal("device_color"), name: name.max(80) }),
  z.object({ kind: z.literal("processor_model"), name: name.max(120), brandId: uuid, familyId: uuid, generationId: uuid, notebook: z.boolean(), desktop: z.boolean() }),
  z.object({ kind: z.literal("gpu_brand"), name: name.max(80) }),
  z.object({ kind: z.literal("gpu_family"), name: name.max(120), brandId: uuid }),
  z.object({ kind: z.literal("gpu_model"), name: name.max(160), familyId: uuid, graphicsKind: z.enum(["INTEGRATED", "DEDICATED"]), notebook: z.boolean(), desktop: z.boolean() }),
  z.object({ kind: z.literal("motherboard_manufacturer"), name: name.max(120) }),
  z.object({ kind: z.literal("motherboard_model"), name, manufacturerId: uuid, deviceTypeIds: z.array(uuid).min(1) }),
  z.object({ kind: z.literal("ram_type"), code: z.string().trim().min(2).max(30), name: name.max(80) }),
  z.object({ kind: z.literal("ram_speed"), ramTypeId: uuid, mhz: z.coerce.number().int().min(100).max(20000) }),
  z.object({ kind: z.literal("storage_option"), entity: z.enum(["storage_interface", "storage_form_factor"]), code: z.string().trim().min(1).max(40), name: name.max(100) }),
  z.object({ kind: z.literal("reception_control"), key: z.string().trim().regex(/^[a-z][a-z0-9_]{1,60}$/), label: name.max(120), description: z.string().trim().max(500), critical: z.boolean(), deviceTypeIds: z.array(uuid).min(1) }),
]);
const toggleSchema = z.object({ entity: z.enum(["device_brand","device_model","device_variant","device_color","processor_model","gpu_brand","gpu_family","gpu_model","motherboard_manufacturer","motherboard_model","ram_type","ram_speed","storage_interface","storage_form_factor","reception_control"]), id: uuid, active: z.boolean() });

export type MasterActionResult = { ok: boolean; message: string };

function errorMessage(code?: string) {
  if (!code) return "No se pudo actualizar el catálogo.";
  if (code.includes("FORBIDDEN")) return "Esta operación requiere una sesión SUPERADMIN activa.";
  if (code.includes("duplicate") || code.includes("unique") || code.includes("23505")) return "Ya existe un registro equivalente en este catálogo.";
  if (code.includes("BRAND_NOT_ALLOWED_FOR_TYPE")) return "La marca no está relacionada con el tipo seleccionado.";
  if (code.includes("COMPATIBILITY")) return "Seleccioná al menos un tipo compatible.";
  return "No se pudo actualizar el catálogo. Revisá las relaciones seleccionadas.";
}

export async function createMasterCatalogItemAction(input: unknown): Promise<MasterActionResult> {
  await requireRole(["SUPERADMIN"]);
  const parsed = createSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisá los datos y relaciones del nuevo registro." };
  const supabase = await createSupabaseServerClient();
  const item = parsed.data;
  let result: { error: { message?: string; code?: string } | null };
  switch (item.kind) {
    case "device_brand": result = await supabase.rpc("superadmin_create_device_brand", { p_name: item.name, p_device_type_ids: item.deviceTypeIds }); break;
    case "device_model": result = await supabase.rpc("superadmin_create_device_model", { p_device_type_id: item.deviceTypeId, p_brand_id: item.brandId, p_name: item.name }); break;
    case "device_variant": result = await supabase.rpc("superadmin_create_device_variant", { p_model_id: item.modelId, p_name: item.name }); break;
    case "device_color": result = await supabase.rpc("superadmin_create_device_color", { p_name: item.name }); break;
    case "processor_model": result = await supabase.rpc("superadmin_create_processor_model", { p_brand_id: item.brandId, p_family_id: item.familyId, p_generation_id: item.generationId, p_name: item.name, p_notebook: item.notebook, p_desktop: item.desktop }); break;
    case "gpu_brand": result = await supabase.rpc("superadmin_create_gpu_brand", { p_name: item.name }); break;
    case "gpu_family": result = await supabase.rpc("superadmin_create_gpu_family", { p_brand_id: item.brandId, p_name: item.name }); break;
    case "gpu_model": result = await supabase.rpc("superadmin_create_gpu_model", { p_family_id: item.familyId, p_name: item.name, p_graphics_kind: item.graphicsKind, p_notebook: item.notebook, p_desktop: item.desktop }); break;
    case "motherboard_manufacturer": result = await supabase.rpc("superadmin_create_motherboard_manufacturer", { p_name: item.name }); break;
    case "motherboard_model": result = await supabase.rpc("superadmin_create_motherboard_model", { p_manufacturer_id: item.manufacturerId, p_name: item.name, p_device_type_ids: item.deviceTypeIds }); break;
    case "ram_type": result = await supabase.rpc("superadmin_create_ram_type", { p_code: item.code, p_name: item.name }); break;
    case "ram_speed": result = await supabase.rpc("superadmin_create_ram_speed", { p_ram_type_id: item.ramTypeId, p_mhz: item.mhz }); break;
    case "storage_option": result = await supabase.rpc("superadmin_create_storage_option", { p_entity: item.entity, p_code: item.code, p_name: item.name }); break;
    case "reception_control": result = await supabase.rpc("superadmin_create_reception_control", { p_key: item.key, p_label: item.label, p_description: item.description, p_critical: item.critical, p_device_type_ids: item.deviceTypeIds }); break;
  }
  if (result.error) return { ok: false, message: errorMessage(`${result.error.code ?? ""} ${result.error.message ?? ""}`) };
  revalidatePath("/superadmin/master"); revalidatePath("/repairs/new");
  return { ok: true, message: "Catálogo actualizado. El cambio ya está disponible para nuevas consultas." };
}

export async function toggleMasterCatalogItemAction(input: unknown): Promise<MasterActionResult> {
  await requireRole(["SUPERADMIN"]);
  const parsed = toggleSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "El registro solicitado no es válido." };
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("superadmin_set_catalog_active", { p_entity: parsed.data.entity, p_id: parsed.data.id, p_active: parsed.data.active });
  if (error) return { ok: false, message: errorMessage(`${error.code ?? ""} ${error.message}`) };
  revalidatePath("/superadmin/master"); revalidatePath("/repairs/new");
  return { ok: true, message: parsed.data.active ? "Registro reactivado." : "Registro desactivado sin borrar su historial." };
}

export async function createProcessorCatalogAction(input: unknown): Promise<MasterActionResult> {
  const legacy = z.object({ brandId: uuid, familyId: uuid, generationId: uuid, model: name }).safeParse(input);
  if (!legacy.success) return { ok: false, message: "Revisá fabricante, familia, serie y modelo." };
  return createMasterCatalogItemAction({ kind: "processor_model", ...legacy.data, notebook: true, desktop: false });
}
