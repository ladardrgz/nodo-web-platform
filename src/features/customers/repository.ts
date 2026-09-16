import "server-only";

import { cache } from "react";
import type { Customer, Device, DeviceType } from "@/features/customers/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const CUSTOMER_SELECT = "id,organization_id,first_name,last_name,contact_email,phone,created_at,customer_devices(id,numero_serie,device_types(name),device_brands(name),device_models(name),device_colors(name))";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Relation<T> = T | T[] | null;
interface DeviceRow { id: string; numero_serie: string | null; device_types: Relation<{ name: string }>; device_brands: Relation<{ name: string }>; device_models: Relation<{ name: string }>; device_colors: Relation<{ name: string }> }
interface CustomerRow { id: string; organization_id: string; first_name: string; last_name: string; contact_email: string | null; phone: string | null; created_at: string; customer_devices: DeviceRow[] | null }
function one<T>(value: Relation<T>): T | null { return Array.isArray(value) ? value[0] ?? null : value; }
function mapType(name: string): DeviceType { return name === "Desktop PC" ? "DESKTOP" : name === "Notebook" ? "NOTEBOOK" : "OTHER"; }
function mapDevice(row: DeviceRow): Device { const type = one(row.device_types); const brand = one(row.device_brands); const model = one(row.device_models); const color = one(row.device_colors); return { id: row.id, type: mapType(type?.name ?? ""), brand: brand?.name ?? "", model: model?.name ?? "", color: color?.name ?? undefined, serialNumber: row.numero_serie ?? undefined }; }
function mapCustomer(row: CustomerRow): Customer { return { id: row.id, firstName: row.first_name, lastName: row.last_name, phone: row.phone ?? "", email: row.contact_email ?? "", preferredContact: row.contact_email ? "EMAIL" : "PHONE", createdAt: row.created_at, devices: (row.customer_devices ?? []).map(mapDevice), history: [] }; }
export async function listOrganizationCustomers(organizationId: string): Promise<Customer[]> { const supabase = await createSupabaseServerClient(); const { data, error } = await supabase.from("customers").select(CUSTOMER_SELECT).eq("organization_id", organizationId).order("last_name").order("first_name"); if (error) throw new Error("CUSTOMERS_READ_FAILED"); return ((data ?? []) as unknown as CustomerRow[]).map(mapCustomer); }
export const getOrganizationCustomer = cache(async (organizationId: string, customerId: string): Promise<Customer | null> => { if (!UUID_PATTERN.test(customerId)) return null; const supabase = await createSupabaseServerClient(); const { data, error } = await supabase.from("customers").select(CUSTOMER_SELECT).eq("organization_id", organizationId).eq("id", customerId).maybeSingle(); return error || !data ? null : mapCustomer(data as unknown as CustomerRow); });
