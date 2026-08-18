import type { InventoryItem } from "@/features/inventory/types";

const featuredInventory: InventoryItem[] = [
  {
    id: "inv-screen-a14",
    name: "Módulo Samsung Galaxy A14",
    code: "MOD-A14-01",
    category: "PART",
    brand: "Samsung",
    compatibility: "Galaxy A14 4G",
    currentStock: 2,
    minimumStock: 2,
    price: 118000,
  },
  {
    id: "inv-battery-a14",
    name: "Batería Samsung A14",
    code: "BAT-A14-02",
    category: "PART",
    brand: "Samsung",
    compatibility: "Galaxy A14",
    currentStock: 0,
    minimumStock: 2,
    price: 42000,
  },
  {
    id: "inv-ssd-500",
    name: "SSD Kingston 500 GB",
    code: "SSD-KIN-500",
    category: "PART",
    brand: "Kingston",
    compatibility: "SATA 2.5 pulgadas",
    currentStock: 8,
    minimumStock: 3,
    price: 86500,
  },
  {
    id: "inv-usbc",
    name: "Conector USB-C universal",
    code: "USB-C-UNI",
    category: "PART",
    compatibility: "Modelos seleccionados",
    currentStock: 3,
    minimumStock: 5,
    price: 14800,
  },
  {
    id: "inv-isopropyl",
    name: "Alcohol isopropílico 1 L",
    code: "CON-ISO-1L",
    category: "CONSUMABLE",
    currentStock: 6,
    minimumStock: 2,
    price: 12400,
  },
];

const generatedInventory: InventoryItem[] = Array.from({ length: 20 }, (_, index) => {
  const code = String(index + 1).padStart(2, "0");
  const category = (["PART", "CONSUMABLE", "ACCESSORY", "SOFTWARE"] as const)[index % 4];
  return {
    id: `demo-inventory-${code}`,
    name: `${category === "PART" ? "Repuesto" : category === "CONSUMABLE" ? "Consumible" : category === "ACCESSORY" ? "Accesorio" : "Licencia"} demo ${code}`,
    code: `DEMO-${category.slice(0, 3)}-${code}`,
    category,
    brand: ["Samsung", "Motorola", "Kingston", "Genérica"][index % 4],
    compatibility: "Referencia ficticia",
    currentStock: index % 6,
    minimumStock: 2,
    price: 10000 + index * 2750,
  };
});

export const mockInventory: InventoryItem[] = [...featuredInventory, ...generatedInventory];
