export type InventoryCategory =
  | "PART"
  | "CONSUMABLE"
  | "ACCESSORY"
  | "SOFTWARE";

export interface InventoryItem {
  id: string;
  name: string;
  code: string;
  category: InventoryCategory;
  brand?: string;
  compatibility?: string;
  currentStock: number;
  minimumStock: number;
  price: number;
}

export const inventoryCategoryLabels: Record<InventoryCategory, string> = {
  PART: "Repuesto",
  CONSUMABLE: "Consumible",
  ACCESSORY: "Accesorio",
  SOFTWARE: "Software",
};
