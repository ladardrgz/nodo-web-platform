import type { PriceItem } from "@/features/pricing/types";

export const mockPrices: PriceItem[] = [
  {
    id: "price-diagnosis-phone",
    name: "Diagnóstico general de celular",
    category: "DIAGNOSIS",
    deviceType: "Celular",
    price: 18000,
    estimatedTime: "24 a 48 horas",
    updatedAt: "2026-08-14T10:00:00-03:00",
  },
  {
    id: "price-screen-a14",
    name: "Cambio de módulo Galaxy A14",
    category: "SCREEN",
    deviceType: "Celular",
    price: 158000,
    estimatedTime: "2 a 3 días",
    updatedAt: "2026-08-15T16:20:00-03:00",
  },
  {
    id: "price-battery-iphone13",
    name: "Cambio de batería iPhone 13",
    category: "BATTERY",
    deviceType: "Celular",
    price: 132000,
    estimatedTime: "1 a 2 días",
    updatedAt: "2026-08-12T09:15:00-03:00",
  },
  {
    id: "price-ssd-clone",
    name: "Instalación SSD y clonación",
    category: "STORAGE",
    deviceType: "Notebook / PC",
    price: 64000,
    estimatedTime: "1 día",
    updatedAt: "2026-08-10T11:30:00-03:00",
  },
  {
    id: "price-os",
    name: "Instalación y configuración de sistema",
    category: "SOFTWARE",
    deviceType: "Notebook / PC",
    price: 48000,
    estimatedTime: "1 día",
    updatedAt: "2026-08-09T12:00:00-03:00",
  },
];
