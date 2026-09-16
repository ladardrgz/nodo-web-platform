import "server-only";

import type { InventoryItem } from "@/features/inventory/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

interface InventoryRow {
  id: string;
  name: string;
  sku: string | null;
  current_stock: number | string;
  minimum_stock: number | string;
  sale_price: number | string;
  inventory_categories: { name: string } | { name: string }[] | null;
  inventory_brands: { name: string } | { name: string }[] | null;
}

function one<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? value[0] ?? null : value;
}

export async function listOrganizationInventory(organizationId: string): Promise<InventoryItem[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("inventory_items")
    .select("id,name,sku,current_stock,minimum_stock,sale_price,inventory_categories(name),inventory_brands(name)")
    .eq("organization_id", organizationId)
    .eq("is_active", true)
    .order("name");

  if (error) throw new Error("INVENTORY_READ_FAILED");

  return ((data ?? []) as unknown as InventoryRow[]).map((item) => ({
    id: item.id,
    name: item.name,
    code: item.sku ?? "Sin código",
    category: one(item.inventory_categories)?.name ?? "Sin categoría",
    brand: one(item.inventory_brands)?.name,
    currentStock: Number(item.current_stock),
    minimumStock: Number(item.minimum_stock),
    price: Number(item.sale_price),
  }));
}
