import type { Customer } from "@/features/customers/types";

const featuredCustomers: Customer[] = [
  {
    id: "lucia-fernandez", firstName: "Lucía", lastName: "Fernández", phone: "+54 370 555-5812", email: "lucia.fernandez@example.test", address: "Av. Independencia 1450, Formosa", preferredContact: "WHATSAPP", createdAt: "2026-08-11T10:12:00-03:00",
    devices: [{ id: "device-a14", type: "PHONE", brand: "Samsung", model: "Galaxy A14", color: "Negro", imei: "•••••••••••4821" }, { id: "device-ideapad", type: "NOTEBOOK", brand: "Lenovo", model: "IdeaPad 3", color: "Gris", serialNumber: "PF-IDEA-2048" }],
    history: [{ id: "history-lucia-1", title: "Cliente creado", description: "Registro ficticio realizado desde recepción.", createdAt: "2026-08-11T10:12:00-03:00" }, { id: "history-lucia-2", title: "Nuevo equipo recibido", description: "Samsung Galaxy A14.", createdAt: "2026-08-16T10:22:00-03:00" }],
  },
  {
    id: "martin-gomez", firstName: "Martín", lastName: "Gómez", phone: "+54 370 555-7290", email: "martin.gomez@example.test", address: "Mitre 824, Formosa", preferredContact: "PHONE", createdAt: "2026-08-12T09:10:00-03:00",
    devices: [{ id: "device-iphone13", type: "PHONE", brand: "Apple", model: "iPhone 13", color: "Azul", imei: "•••••••••••1094" }],
    history: [{ id: "history-martin-1", title: "Recepción confirmada", description: "Se entregó el equipo sin cargador.", createdAt: "2026-08-12T09:10:00-03:00" }],
  },
  {
    id: "sofia-acosta", firstName: "Sofía", lastName: "Acosta", phone: "+54 370 555-2301", email: "sofia.acosta@example.test", preferredContact: "EMAIL", createdAt: "2026-07-28T14:30:00-03:00",
    devices: [{ id: "device-g54", type: "PHONE", brand: "Motorola", model: "Moto G54", color: "Verde" }],
    history: [{ id: "history-sofia-1", title: "Equipo listo", description: "Se notificó disponibilidad para retiro.", createdAt: "2026-08-16T09:40:00-03:00" }],
  },
  {
    id: "diego-rojas", firstName: "Diego", lastName: "Rojas", phone: "+54 370 555-1137", email: "diego.rojas@example.test", preferredContact: "WHATSAPP", createdAt: "2026-06-19T08:55:00-03:00",
    devices: [{ id: "device-pavilion", type: "NOTEBOOK", brand: "HP", model: "Pavilion 15", color: "Plateado", serialNumber: "HP-PAV-8817" }], history: [],
  },
];

const demoNames = [
  ["Valentina", "Benítez"], ["Joaquín", "Cáceres"], ["Camila", "Vera"], ["Mateo", "Insfrán"],
  ["Emilia", "Giménez"], ["Thiago", "Sosa"], ["Renata", "Romero"], ["Benjamín", "Medina"],
  ["Mía", "Paredes"], ["Bautista", "Díaz"], ["Catalina", "López"], ["Felipe", "Ortiz"],
  ["Josefina", "Silva"], ["Bruno", "Ramírez"], ["Delfina", "Torres"], ["Lautaro", "Núñez"],
  ["Agustina", "Caballero"], ["Franco", "Cardozo"], ["Julieta", "Villalba"], ["Santino", "Leiva"],
  ["Malena", "Aguirre"], ["Tomás", "Ponce"], ["Abril", "Escobar"], ["Nicolás", "Maidana"],
  ["Victoria", "Ferreyra"], ["Ramiro", "Domínguez"], ["Alma", "Godoy"], ["Facundo", "Coronel"],
] as const;

const generatedCustomers: Customer[] = demoNames.map(([firstName, lastName], index) => {
  const code = String(index + 1).padStart(2, "0");
  const createdDay = String((index % 27) + 1).padStart(2, "0");
  return {
    id: `demo-customer-${code}`,
    firstName,
    lastName,
    phone: `+54 370 555-${String(3000 + index).padStart(4, "0")}`,
    email: `cliente${code}@example.test`,
    preferredContact: (["WHATSAPP", "EMAIL", "PHONE"] as const)[index % 3],
    createdAt: `2026-${index < 12 ? "08" : "07"}-${createdDay}T10:00:00-03:00`,
    devices: index % 3 === 0 ? [{ id: `demo-device-${code}`, type: "PHONE", brand: ["Samsung", "Motorola", "Xiaomi"][index % 3], model: `Modelo demo ${code}`, color: "Negro" }] : [],
    history: [],
  };
});

export const mockCustomers: Customer[] = [...featuredCustomers, ...generatedCustomers];
