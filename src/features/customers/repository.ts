import "server-only";

import { cache } from "react";
import type { Customer, Device, DeviceType } from "@/features/customers/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const CUSTOMER_SELECT = "id,organization_id,first_name,last_name,contact_email,phone,created_at,customer_devices(id,model,color,serial_number,imei_1,device_types(name,attribute_group),device_brands(name))";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
interface CatalogRelation { name: string; attribute_group?: string }
interface DeviceRow { id: string; model: string; color: string | null; serial_number: string | null; imei_1: string | null; device_types: CatalogRelation | CatalogRelation[] | null; device_brands: CatalogRelation | CatalogRelation[] | null }
interface CustomerRow { id: string; organization_id: string; first_name: string; last_name: string; contact_email: string | null; phone: string | null; created_at: string; customer_devices: DeviceRow[] | null }
function one<T>(value: T | T[] | null): T | null { return Array.isArray(value) ? value[0] ?? null : value; }
function legacyType(group: string | undefined, name: string): DeviceType { if (name.toLocaleLowerCase("es").includes("tablet") || name === "iPad") return "TABLET"; if (group === "MOBILE") return "PHONE"; if (group === "COMPUTER") return name.toLocaleLowerCase("es").includes("pc") || name === "Workstation" || name === "Servidor" ? "DESKTOP" : "NOTEBOOK"; return "OTHER"; }
function mapDevice(row: DeviceRow): Device { const type = one(row.device_types); const brand = one(row.device_brands); return { id: row.id, type: legacyType(type?.attribute_group, type?.name ?? ""), brand: brand?.name ?? "Sin marca", model: row.model, color: row.color ?? undefined, serialNumber: row.serial_number ?? undefined, imei: row.imei_1 ?? undefined }; }
function mapCustomer(row: CustomerRow): Customer { return { id: row.id, firstName: row.first_name, lastName: row.last_name, phone: row.phone ?? "Sin teléfono", email: row.contact_email ?? "", preferredContact: row.contact_email ? "EMAIL" : "PHONE", createdAt: row.created_at, devices: (row.customer_devices ?? []).map(mapDevice), history: [] }; }

export async function listOrganizationCustomers(organizationId: string): Promise<Customer[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("customers").select(CUSTOMER_SELECT).eq("organization_id", organizationId).order("last_name").order("first_name");
  if (error) throw new Error("CUSTOMERS_READ_FAILED");
  return ((data ?? []) as unknown as CustomerRow[]).map(mapCustomer);
}

export const getOrganizationCustomer = cache(async (organizationId: string, customerId: string): Promise<Customer | null> => {
  if (!UUID_PATTERN.test(customerId)) return null;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("customers").select(CUSTOMER_SELECT).eq("organization_id", organizationId).eq("id", customerId).maybeSingle();
  if (error || !data) return null;
  return mapCustomer(data as unknown as CustomerRow);
});
