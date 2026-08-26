"use server";

import { revalidatePath } from "next/cache";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { customCatalogSchema, customerFieldErrors, deviceSchema, newCustomerSchema, photoMetadataSchema, receptionSchema } from "./schemas";
import { serializeInspection } from "./inspection";
import type { CatalogOption, MutationResult, ReceptionCustomer } from "./types";

function controlledError(error: unknown, fallback: string): string {
  const message = error && typeof error === "object" && "message" in error ? String(error.message) : "";
  if (message.includes("CUSTOMER_PHONE_EXISTS")) return "Este teléfono ya pertenece a un cliente registrado.";
  if (message.includes("CUSTOMER_EMAIL_EXISTS")) return "Este correo electrónico ya pertenece a un cliente registrado.";
  if (message.includes("DEVICE_TYPE_EXISTS")) return "Este tipo de dispositivo ya existe.";
  if (message.includes("DEVICE_BRAND_EXISTS")) return "Esta marca ya está registrada.";
  if (message.includes("INVALID_INSPECTION")) return "La inspección contiene un estado no válido. Revisá el checklist e intentá nuevamente.";
  if (message.includes("INVALID_RECEPTION")) return "La recepción está incompleta. Revisá el problema informado y la inspección física.";
  if (message.includes("INVALID_DEVICE")) return "El dispositivo seleccionado no pertenece al cliente actual.";
  return fallback;
}

export async function createCustomerAction(input: unknown): Promise<MutationResult<ReceptionCustomer>> {
  const parsed = newCustomerSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisá los datos del cliente.", fieldErrors: customerFieldErrors(parsed.error) };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("create_reception_customer", { p_first_name: parsed.data.firstName, p_last_name: parsed.data.lastName, p_phone: parsed.data.phone, p_contact_email: parsed.data.email || null }).single();
  if (error || !data) { const message = controlledError(error, "No se pudo registrar el cliente."); return { ok: false, message, fieldErrors: message.includes("teléfono") ? { phone: message } : message.includes("correo") ? { email: message } : undefined }; }
  const row = data as { id: string; first_name: string; last_name: string; phone: string; contact_email: string | null };
  revalidatePath("/repairs/new");
  return { ok: true, message: "Cliente registrado correctamente.", data: { id: row.id, firstName: row.first_name, lastName: row.last_name, phone: row.phone, email: row.contact_email ?? "" } };
}

async function createCatalog(kind: "type" | "brand", input: unknown): Promise<MutationResult<CatalogOption>> {
  const parsed = customCatalogSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: kind === "type" ? "Ingresá un nombre de tipo válido." : "Ingresá un nombre de marca válido.", fieldErrors: { name: "El nombre debe tener al menos 2 caracteres." } };
  await requireOwnerOrganization(); const supabase = await createSupabaseServerClient();
  const rpc = kind === "type" ? "create_custom_device_type" : "create_custom_device_brand";
  const { data, error } = await supabase.rpc(rpc, { p_name: parsed.data.name }).single();
  if (error || !data) return { ok: false, message: controlledError(error, kind === "type" ? "No se pudo registrar el tipo de dispositivo." : "No se pudo registrar la marca.") };
  const row = data as { id: string; name: string; category?: string; attribute_group?: string; organization_id: string };
  return { ok: true, message: kind === "type" ? "Tipo de dispositivo registrado correctamente." : "Marca registrada correctamente.", data: { id: row.id, name: row.name, category: row.category, attributeGroup: (row.attribute_group ?? "OTHER") as CatalogOption["attributeGroup"], organizationId: row.organization_id } };
}
export async function createCustomDeviceTypeAction(input: unknown) { return createCatalog("type", input); }
export async function createCustomBrandAction(input: unknown) { return createCatalog("brand", input); }

export async function saveDeviceAction(input: unknown): Promise<MutationResult<{ id: string }>> {
  const parsed = deviceSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisá los datos del dispositivo.", fieldErrors: customerFieldErrors(parsed.error) };
  await requireOwnerOrganization(); const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("create_customer_device", { p_customer_id: parsed.data.customerId, p_type_id: parsed.data.typeId, p_brand_id: parsed.data.brandId, p_model: parsed.data.model, p_year: parsed.data.year || null, p_color: parsed.data.color || null, p_serial_number: parsed.data.serialNumber || null, p_imei_1: parsed.data.imei1 || null, p_imei_2: parsed.data.imei2 || null, p_attributes: parsed.data.attributes, p_memories: parsed.data.memories, p_storage_units: parsed.data.storageUnits, p_accessories: parsed.data.accessories });
  if (error || !data) return { ok: false, message: "No se pudieron guardar los datos del dispositivo." };
  revalidatePath("/repairs/new"); return { ok: true, message: "Datos del dispositivo guardados correctamente.", data: { id: String(data) } };
}

export async function confirmReceptionAction(input: unknown): Promise<MutationResult<{ id: string; photoPrefix: string }>> {
  const parsed = receptionSchema.safeParse(input);
  if (!parsed.success) return { ok: false, message: "Revisá la inspección de recepción.", fieldErrors: customerFieldErrors(parsed.error) };
  const { organization } = await requireOwnerOrganization(); const supabase = await createSupabaseServerClient();
  const databaseInspection = serializeInspection(parsed.data.inspection);
  const { data, error } = await supabase.rpc("confirm_device_reception", { p_customer_id: parsed.data.customerId, p_device_id: parsed.data.deviceId, p_reported_problem: parsed.data.reportedProblem, p_observations: parsed.data.observations, p_inspection: databaseInspection });
  if (error || !data) return { ok: false, message: controlledError(error, "No se pudo registrar la recepción.") };
  const id = String(data); revalidatePath("/repairs");
  return { ok: true, message: "Recepción registrada correctamente.", data: { id, photoPrefix: `${organization.id}/${id}` } };
}

export async function registerReceptionPhotoAction(input: unknown): Promise<MutationResult<{ id: string }>> {
  const parsed = photoMetadataSchema.safeParse(input); if (!parsed.success) return { ok: false, message: "No se pudo cargar la fotografía." };
  const { organization } = await requireOwnerOrganization();
  if (!parsed.data.storagePath.startsWith(`${organization.id}/${parsed.data.receptionId}/`)) return { ok: false, message: "No se pudo cargar la fotografía." };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("register_reception_photo", { p_reception_id: parsed.data.receptionId, p_storage_path: parsed.data.storagePath, p_description: parsed.data.description || null, p_inspection_key: parsed.data.inspectionKey || null });
  if (error || !data) return { ok: false, message: "No se pudo cargar la fotografía." };
  return { ok: true, message: "Fotografía agregada correctamente.", data: { id: String(data) } };
}
