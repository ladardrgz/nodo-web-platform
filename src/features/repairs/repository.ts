import "server-only";

import { cache } from "react";
import type { DeviceType } from "@/features/customers/types";
import { REPAIR_STATUS, type RepairDetail, type RepairOrder } from "@/features/repairs/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const RECEPTION_SELECT = "id,organization_id,customer_id,device_id,reported_problem,observations,condition_score,calculated_condition,status,created_at,customers(first_name,last_name),customer_devices(model,color,serial_number,imei_1,accessories,device_types(name,attribute_group),device_brands(name))";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface RelationCustomer { first_name: string; last_name: string }
interface RelationCatalog { name: string; attribute_group?: string }
interface RelationDevice { model: string; color: string | null; serial_number: string | null; imei_1: string | null; accessories: string[] | null; device_types: RelationCatalog | RelationCatalog[] | null; device_brands: RelationCatalog | RelationCatalog[] | null }
interface ReceptionRow { id: string; organization_id: string; customer_id: string; device_id: string; reported_problem: string; observations: string; condition_score: number; calculated_condition: string; status: string; created_at: string; customers: RelationCustomer | RelationCustomer[] | null; customer_devices: RelationDevice | RelationDevice[] | null }

function one<T>(value: T | T[] | null): T | null { return Array.isArray(value) ? value[0] ?? null : value; }
function legacyDeviceType(group: string | undefined, name: string): DeviceType {
  if (name.toLocaleLowerCase("es").includes("tablet") || name === "iPad") return "TABLET";
  if (group === "MOBILE") return "PHONE";
  if (group === "COMPUTER") return name.toLocaleLowerCase("es").includes("pc") || name === "Workstation" || name === "Servidor" ? "DESKTOP" : "NOTEBOOK";
  return "OTHER";
}
function orderNumber(id: string): string { return `REC-${id.slice(0, 8).toUpperCase()}`; }

function mapReception(row: ReceptionRow): RepairOrder {
  const customer = one(row.customers); const device = one(row.customer_devices); const type = one(device?.device_types ?? null); const brand = one(device?.device_brands ?? null);
  const customerName = [customer?.first_name, customer?.last_name].filter(Boolean).join(" ") || "Cliente sin nombre";
  const deviceTypeName = type?.name ?? "Dispositivo";
  return {
    id: row.id, orderNumber: orderNumber(row.id), customerId: row.customer_id, customerName,
    device: { id: row.device_id, type: legacyDeviceType(type?.attribute_group, deviceTypeName), brand: brand?.name ?? "Sin marca", model: device?.model ?? "Sin modelo", color: device?.color ?? undefined, serialNumber: device?.serial_number ?? undefined, imei: device?.imei_1 ?? undefined },
    deviceTypeName, status: REPAIR_STATUS.RECEIVED, intakeStatus: "CONFIRMED", receivedAt: row.created_at, updatedAt: row.created_at,
    reportedProblem: row.reported_problem, intakeNotes: row.observations || `Estado físico calculado: ${row.calculated_condition}.`, accessories: device?.accessories ?? [],
    timeline: [{ id: `${row.id}-received`, title: "Recepción registrada", description: `El equipo ingresó con estado calculado: ${row.calculated_condition}.`, createdAt: row.created_at, actor: "ADMIN" }],
  };
}

export async function listOrganizationRepairs(organizationId: string, limit = 500): Promise<RepairOrder[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("device_receptions").select(RECEPTION_SELECT).eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(Math.min(Math.max(limit, 1), 500));
  if (error) throw new Error("REPAIRS_READ_FAILED");
  return ((data ?? []) as unknown as ReceptionRow[]).map(mapReception);
}

export const getOrganizationRepair = cache(async (organizationId: string, receptionId: string): Promise<RepairDetail | null> => {
  if (!UUID_PATTERN.test(receptionId)) return null;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("device_receptions").select(RECEPTION_SELECT).eq("organization_id", organizationId).eq("id", receptionId).maybeSingle();
  if (error || !data) return null;
  const [inspectionResult, photosResult] = await Promise.all([
    supabase.from("reception_inspection_items").select("id,item_key,label,condition,severity,observation,is_critical").eq("organization_id", organizationId).eq("reception_id", receptionId).order("created_at"),
    supabase.from("reception_photos").select("id,storage_path,description,inspection_item_key,created_at").eq("organization_id", organizationId).eq("reception_id", receptionId).order("created_at"),
  ]);
  if (inspectionResult.error || photosResult.error) throw new Error("REPAIR_DETAIL_READ_FAILED");
  const photos = await Promise.all((photosResult.data ?? []).map(async (photo) => {
    const signed = await supabase.storage.from("reception-photos").createSignedUrl(photo.storage_path, 3_600);
    return { id: photo.id, url: signed.data?.signedUrl ?? "", description: photo.description, inspectionItemKey: photo.inspection_item_key, createdAt: photo.created_at };
  }));
  const row = data as unknown as ReceptionRow;
  return {
    ...mapReception(row), calculatedCondition: row.calculated_condition, conditionScore: Number(row.condition_score),
    inspection: (inspectionResult.data ?? []).map((item) => ({ id: item.id, key: item.item_key, label: item.label, condition: item.condition, severity: item.severity === null ? null : Number(item.severity), observation: item.observation, critical: item.is_critical })),
    photos: photos.filter((photo) => photo.url),
  };
});
