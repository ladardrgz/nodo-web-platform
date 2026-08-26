import type { DeviceAttributeGroup } from "./types";

export const DEVICE_TYPE_SEEDS = [
  ["Telefonía y dispositivos móviles", "Celular / Smartphone", "MOBILE"], ["Telefonía y dispositivos móviles", "Teléfono básico", "MOBILE"], ["Telefonía y dispositivos móviles", "Tablet", "MOBILE"], ["Telefonía y dispositivos móviles", "iPad", "MOBILE"], ["Telefonía y dispositivos móviles", "Smartwatch", "MOBILE"], ["Telefonía y dispositivos móviles", "Smartband", "MOBILE"], ["Telefonía y dispositivos móviles", "GPS", "MOBILE"],
  ["Computación", "Notebook", "COMPUTER"], ["Computación", "Ultrabook", "COMPUTER"], ["Computación", "Netbook", "COMPUTER"], ["Computación", "Chromebook", "COMPUTER"], ["Computación", "MacBook", "COMPUTER"], ["Computación", "PC de escritorio", "COMPUTER"], ["Computación", "PC gamer", "COMPUTER"], ["Computación", "All-in-One", "COMPUTER"], ["Computación", "Mini PC", "COMPUTER"], ["Computación", "Workstation", "COMPUTER"], ["Computación", "Servidor", "COMPUTER"],
  ["Componentes", "Placa madre", "OTHER"], ["Componentes", "Placa de video", "OTHER"], ["Componentes", "Fuente ATX", "POWER"], ["Componentes", "Fuente de alimentación", "POWER"], ["Componentes", "Disco externo", "STORAGE"], ["Componentes", "SSD externo", "STORAGE"], ["Componentes", "Pendrive", "STORAGE"], ["Componentes", "Lector de tarjetas", "STORAGE"],
  ["Imagen y visualización", "Monitor", "DISPLAY"], ["Imagen y visualización", "Smart TV", "DISPLAY"], ["Imagen y visualización", "TV LED/LCD", "DISPLAY"], ["Imagen y visualización", "Proyector", "DISPLAY"], ["Imagen y visualización", "Cámara digital", "CAMERA"], ["Imagen y visualización", "Cámara IP", "CAMERA"], ["Imagen y visualización", "Webcam", "CAMERA"],
  ["Impresión", "Impresora láser", "PRINTER"], ["Impresión", "Impresora tinta", "PRINTER"], ["Impresión", "Impresora multifunción", "PRINTER"], ["Impresión", "Impresora térmica", "PRINTER"], ["Impresión", "Impresora de etiquetas", "PRINTER"], ["Impresión", "Scanner", "PRINTER"], ["Impresión", "Fotocopiadora", "PRINTER"],
  ["Redes", "Router", "NETWORK"], ["Redes", "Módem", "NETWORK"], ["Redes", "Access Point", "NETWORK"], ["Redes", "Repetidor Wi-Fi", "NETWORK"], ["Redes", "Switch de red", "NETWORK"], ["Redes", "NAS", "STORAGE"], ["Redes", "DVR", "NETWORK"], ["Redes", "NVR", "NETWORK"],
  ["Gaming", "Consola de videojuegos", "GAMING"], ["Gaming", "Consola portátil", "GAMING"], ["Gaming", "Joystick / Gamepad", "PERIPHERAL"],
  ["Periféricos", "Teclado", "PERIPHERAL"], ["Periféricos", "Mouse", "PERIPHERAL"], ["Periféricos", "Auriculares", "AUDIO"], ["Periféricos", "Parlante", "AUDIO"],
  ["Energía", "UPS", "POWER"], ["Energía", "Estabilizador", "POWER"], ["Audio y multimedia", "Equipo de audio", "AUDIO"], ["Audio y multimedia", "Home theater", "AUDIO"], ["Audio y multimedia", "Decodificador / TV Box", "AUDIO"], ["Comercial", "POS / Terminal de venta", "COMMERCIAL"], ["Comercial", "Lector de código de barras", "COMMERCIAL"],
] as const satisfies readonly (readonly [string, string, DeviceAttributeGroup])[];

export const BRAND_NAMES = ["Apple", "Samsung", "Xiaomi", "Motorola", "Huawei", "Lenovo", "HP", "Dell", "ASUS", "Acer", "MSI", "Gigabyte", "Intel", "AMD", "Epson", "Canon", "Brother", "Lexmark", "Sony", "LG", "TCL", "Philips", "TP-Link", "Logitech", "Kingston", "Western Digital", "Seagate", "Crucial", "Corsair", "HyperX", "Razer", "Microsoft", "Nintendo", "PlayStation / Sony", "Xbox / Microsoft", "Hikvision", "Dahua", "JBL", "Bose", "Noblex", "RCA"] as const;

export const COLORS = ["Negro", "Blanco", "Gris", "Gris espacial", "Plata", "Titanio natural", "Titanio negro", "Titanio blanco", "Dorado", "Gold", "Rose Gold", "Azul", "Azul oscuro", "Azul marino", "Celeste", "Rojo", "Verde", "Verde oliva", "Violeta", "Morado", "Rosa", "Beige", "Crema", "Grafito", "Carbón", "Bronce", "Cobre", "Champagne", "Midnight", "Starlight", "Product Red", "Otro color"] as const;
export const ACCESSORIES = ["Cargador", "Fuente", "Cable USB", "Cable USB-C", "Cable Lightning", "Cable HDMI", "Funda", "Bolso", "Caja", "Batería", "Mouse", "Teclado", "Adaptador", "Pendrive", "Memoria SD", "Stylus", "Control remoto", "Base", "Auriculares"] as const;

export const ATTRIBUTE_FIELDS: Record<DeviceAttributeGroup, { key: string; label: string; suggestion?: "processors" | "motherboards" | "gpus" }[]> = {
  MOBILE: [{ key: "storage", label: "Almacenamiento" }, { key: "ram", label: "RAM" }],
  COMPUTER: [{ key: "motherboard", label: "Motherboard", suggestion: "motherboards" }, { key: "processor", label: "Procesador", suggestion: "processors" }, { key: "gpu", label: "GPU / placa de video", suggestion: "gpus" }, { key: "operatingSystem", label: "Sistema operativo" }],
  PRINTER: [{ key: "printType", label: "Tipo de impresión" }, { key: "technology", label: "Tecnología" }, { key: "connectivity", label: "Conectividad" }],
  DISPLAY: [{ key: "screenSize", label: "Tamaño de pantalla" }, { key: "resolution", label: "Resolución" }, { key: "connectivity", label: "Conectividad" }],
  NETWORK: [{ key: "connectivity", label: "Conectividad" }, { key: "ports", label: "Puertos" }],
  GAMING: [{ key: "storage", label: "Almacenamiento" }, { key: "edition", label: "Edición" }],
  CAMERA: [{ key: "resolution", label: "Resolución" }, { key: "connectivity", label: "Conectividad" }],
  STORAGE: [{ key: "capacity", label: "Capacidad" }, { key: "storageType", label: "Tipo de almacenamiento" }],
  AUDIO: [{ key: "connectivity", label: "Conectividad" }, { key: "power", label: "Potencia" }],
  PERIPHERAL: [{ key: "connectivity", label: "Conectividad" }], POWER: [{ key: "power", label: "Potencia" }],
  COMMERCIAL: [{ key: "connectivity", label: "Conectividad" }], OTHER: [],
};
