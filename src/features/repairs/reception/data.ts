import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { CatalogOption, ReceptionFormData } from "./types";

interface CatalogRow { id: string; name: string; category?: string; attribute_group?: string; organization_id: string | null; categories?: string[] }
function mapCatalog(row: CatalogRow): CatalogOption { return { id: row.id, name: row.name, category: row.category, attributeGroup: row.attribute_group as CatalogOption["attributeGroup"], organizationId: row.organization_id, categories: row.categories ?? [] }; }

export async function getReceptionFormData(organizationId: string): Promise<ReceptionFormData> {
  const supabase = await createSupabaseServerClient();
  const [customersResult, typesResult, brandsResult, devicesResult] = await Promise.all([
    supabase.from("customers").select("id,first_name,last_name,phone,contact_email").eq("organization_id", organizationId).order("last_name"),
    supabase.from("device_types").select("id,name,category,attribute_group,organization_id").or(`organization_id.is.null,organization_id.eq.${organizationId}`).eq("is_active", true).order("category").order("name"),
    supabase.from("device_brands").select("id,name,categories,organization_id").or(`organization_id.is.null,organization_id.eq.${organizationId}`).eq("is_active", true).order("name"),
    supabase.from("customer_devices").select("model,attributes").eq("organization_id", organizationId).limit(250),
  ]);
  if (customersResult.error || typesResult.error || brandsResult.error) throw new Error("RECEPTION_SCHEMA_UNAVAILABLE");
  const values = { models: new Set<string>(), processors: new Set<string>(), motherboards: new Set<string>(), gpus: new Set<string>() };
  for (const row of devicesResult.data ?? []) {
    if (row.model) values.models.add(row.model);
    const attributes = (row.attributes ?? {}) as Record<string, unknown>;
    if (typeof attributes.processor === "string") values.processors.add(attributes.processor);
    if (typeof attributes.motherboard === "string") values.motherboards.add(attributes.motherboard);
    if (typeof attributes.gpu === "string") values.gpus.add(attributes.gpu);
  }
  return {
    customers: (customersResult.data ?? []).map((row) => ({ id: row.id, firstName: row.first_name, lastName: row.last_name, phone: row.phone ?? "", email: row.contact_email ?? "" })),
    deviceTypes: (typesResult.data ?? []).map((row) => mapCatalog(row as CatalogRow)), brands: (brandsResult.data ?? []).map((row) => mapCatalog(row as CatalogRow)),
    suggestions: { models: [...values.models], processors: [...values.processors], motherboards: [...values.motherboards], gpus: [...values.gpus] },
  };
}
