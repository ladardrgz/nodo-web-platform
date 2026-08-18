export type PriceCategory =
  | "SCREEN"
  | "BATTERY"
  | "DIAGNOSIS"
  | "STORAGE"
  | "SOFTWARE"
  | "OTHER";

export interface PriceItem {
  id: string;
  name: string;
  category: PriceCategory;
  deviceType: string;
  price: number;
  estimatedTime: string;
  updatedAt: string;
}

export const priceCategoryLabels: Record<PriceCategory, string> = {
  SCREEN: "Pantalla",
  BATTERY: "Batería",
  DIAGNOSIS: "Diagnóstico",
  STORAGE: "Almacenamiento",
  SOFTWARE: "Software",
  OTHER: "Otro",
};
