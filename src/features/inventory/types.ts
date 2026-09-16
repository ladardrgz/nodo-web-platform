export interface InventoryItem {
  id: string;
  name: string;
  code: string;
  category: string;
  brand?: string;
  compatibility?: string;
  currentStock: number;
  minimumStock: number;
  price: number;
}
