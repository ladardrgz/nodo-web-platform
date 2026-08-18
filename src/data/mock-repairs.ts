import {
  REPAIR_STATUS,
  type RepairOrder,
} from "@/features/repairs/types";
import { mockCustomers } from "@/data/mock-customers";

const featuredRepairs: RepairOrder[] = [
  {
    id: "rep-000145",
    orderNumber: "REP-2026-000145",
    customerId: "lucia-fernandez",
    customerName: "Lucía Fernández",
    device: {
      id: "device-a14",
      type: "PHONE",
      brand: "Samsung",
      model: "Galaxy A14",
      color: "Negro",
      imei: "•••••••••••4821",
    },
    status: REPAIR_STATUS.WAITING_APPROVAL,
    intakeStatus: "CONFIRMED",
    receivedAt: "2026-08-16T10:22:00-03:00",
    updatedAt: "2026-08-16T16:31:00-03:00",
    estimatedDate: "2026-08-19T18:00:00-03:00",
    reportedProblem: "La pantalla no responde en el sector inferior.",
    intakeNotes: "Rayón leve en tapa. Sin humedad visible.",
    accessories: ["Funda transparente"],
    timeline: [
      {
        id: "event-145-1",
        title: "Equipo recibido",
        description: "Recepción confirmada por administración.",
        createdAt: "2026-08-16T10:22:00-03:00",
        actor: "ADMIN",
      },
      {
        id: "event-145-2",
        title: "Diagnóstico iniciado",
        description: "Se inició la revisión del módulo táctil.",
        createdAt: "2026-08-16T12:08:00-03:00",
        actor: "ADMIN",
      },
      {
        id: "event-145-3",
        title: "Presupuesto disponible",
        description: "Pendiente de aprobación del cliente.",
        createdAt: "2026-08-16T16:31:00-03:00",
        actor: "SYSTEM",
      },
    ],
  },
  {
    id: "rep-000144",
    orderNumber: "REP-2026-000144",
    customerId: "lucia-fernandez",
    customerName: "Lucía Fernández",
    device: {
      id: "device-ideapad",
      type: "NOTEBOOK",
      brand: "Lenovo",
      model: "IdeaPad 3",
      color: "Gris",
      serialNumber: "PF-IDEA-2048",
    },
    status: REPAIR_STATUS.WAITING_PART,
    intakeStatus: "CONFIRMED",
    receivedAt: "2026-08-14T11:05:00-03:00",
    updatedAt: "2026-08-16T11:20:00-03:00",
    estimatedDate: "2026-08-21T18:00:00-03:00",
    reportedProblem: "No inicia y emite un sonido intermitente.",
    intakeNotes: "Equipo con cargador original. Bisagra derecha con juego.",
    accessories: ["Cargador original"],
    timeline: [
      {
        id: "event-144-1",
        title: "Equipo recibido",
        createdAt: "2026-08-14T11:05:00-03:00",
        actor: "ADMIN",
      },
      {
        id: "event-144-2",
        title: "Esperando repuesto",
        description: "Se solicitó el conector de alimentación.",
        createdAt: "2026-08-16T11:20:00-03:00",
        actor: "ADMIN",
      },
    ],
  },
  {
    id: "rep-000143",
    orderNumber: "REP-2026-000143",
    customerId: "martin-gomez",
    customerName: "Martín Gómez",
    device: {
      id: "device-iphone13",
      type: "PHONE",
      brand: "Apple",
      model: "iPhone 13",
      color: "Azul",
      imei: "•••••••••••1094",
    },
    status: REPAIR_STATUS.DELAYED,
    intakeStatus: "CONFIRMED",
    receivedAt: "2026-08-12T09:10:00-03:00",
    updatedAt: "2026-08-15T17:45:00-03:00",
    reportedProblem: "Se reinicia al utilizar la cámara.",
    intakeNotes: "Golpe visible en esquina superior derecha.",
    accessories: [],
    timeline: [
      {
        id: "event-143-1",
        title: "Equipo recibido",
        createdAt: "2026-08-12T09:10:00-03:00",
        actor: "ADMIN",
      },
      {
        id: "event-143-2",
        title: "Reparación demorada",
        description: "Se requieren pruebas adicionales de placa.",
        createdAt: "2026-08-15T17:45:00-03:00",
        actor: "ADMIN",
      },
    ],
  },
  {
    id: "rep-000142",
    orderNumber: "REP-2026-000142",
    customerId: "sofia-acosta",
    customerName: "Sofía Acosta",
    device: {
      id: "device-g54",
      type: "PHONE",
      brand: "Motorola",
      model: "Moto G54",
      color: "Verde",
    },
    status: REPAIR_STATUS.READY_FOR_PICKUP,
    intakeStatus: "CONFIRMED",
    receivedAt: "2026-08-13T14:30:00-03:00",
    updatedAt: "2026-08-16T09:40:00-03:00",
    reportedProblem: "El conector USB sólo carga en una posición.",
    intakeNotes: "Sin daños visibles. Equipo encendido.",
    accessories: ["Cable USB-C"],
    timeline: [
      {
        id: "event-142-1",
        title: "Equipo recibido",
        createdAt: "2026-08-13T14:30:00-03:00",
        actor: "ADMIN",
      },
      {
        id: "event-142-2",
        title: "Equipo listo para retirar",
        description: "Cambio de conector completado y probado.",
        createdAt: "2026-08-16T09:40:00-03:00",
        actor: "ADMIN",
      },
    ],
  },
  {
    id: "rep-000141",
    orderNumber: "REP-2026-000141",
    customerId: "diego-rojas",
    customerName: "Diego Rojas",
    device: {
      id: "device-pavilion",
      type: "NOTEBOOK",
      brand: "HP",
      model: "Pavilion 15",
      color: "Plateado",
      serialNumber: "HP-PAV-8817",
    },
    status: REPAIR_STATUS.DIAGNOSING,
    intakeStatus: "CONFIRMED",
    receivedAt: "2026-08-16T08:55:00-03:00",
    updatedAt: "2026-08-16T10:10:00-03:00",
    reportedProblem: "Funciona lentamente y se apaga con batería.",
    intakeNotes: "Desgaste normal. Sin golpes visibles.",
    accessories: ["Cargador genérico"],
    timeline: [
      {
        id: "event-141-1",
        title: "Equipo recibido",
        createdAt: "2026-08-16T08:55:00-03:00",
        actor: "ADMIN",
      },
      {
        id: "event-141-2",
        title: "Diagnóstico iniciado",
        createdAt: "2026-08-16T10:10:00-03:00",
        actor: "ADMIN",
      },
    ],
  },
];

const generatedStatuses = [
  REPAIR_STATUS.RECEIVED,
  REPAIR_STATUS.DIAGNOSING,
  REPAIR_STATUS.WAITING_APPROVAL,
  REPAIR_STATUS.WAITING_PART,
  REPAIR_STATUS.IN_REPAIR,
  REPAIR_STATUS.DELAYED,
  REPAIR_STATUS.READY_FOR_PICKUP,
  REPAIR_STATUS.DELIVERED,
] as const;

const generatedRepairs: RepairOrder[] = mockCustomers.slice(4).map((customer, index) => {
  const sequence = 140 - index;
  const code = String(sequence).padStart(6, "0");
  const day = String((index % 27) + 1).padStart(2, "0");
  const deviceType = index % 4 === 0 ? "NOTEBOOK" : "PHONE";
  return {
    id: `demo-repair-${code}`,
    orderNumber: `REP-2026-${code}`,
    customerId: customer.id,
    customerName: `${customer.firstName} ${customer.lastName}`,
    device: {
      id: `demo-repair-device-${code}`,
      type: deviceType,
      brand: deviceType === "NOTEBOOK" ? ["Lenovo", "HP", "Asus"][index % 3] : ["Samsung", "Motorola", "Xiaomi"][index % 3],
      model: `Equipo demo ${String(index + 1).padStart(2, "0")}`,
      color: ["Negro", "Azul", "Gris"][index % 3],
    },
    status: generatedStatuses[index % generatedStatuses.length],
    intakeStatus: "CONFIRMED",
    receivedAt: `2026-${index < 14 ? "08" : "07"}-${day}T09:30:00-03:00`,
    updatedAt: `2026-08-${String((index % 16) + 1).padStart(2, "0")}T15:20:00-03:00`,
    reportedProblem: ["No enciende.", "Pantalla dañada.", "Batería con poca autonomía.", "Falla intermitente de carga."][index % 4],
    intakeNotes: "Orden ficticia para validar navegación, filtros y paginación.",
    accessories: [],
    timeline: [{ id: `demo-event-${code}`, title: "Equipo recibido", description: "Evento ficticio de demostración.", createdAt: `2026-${index < 14 ? "08" : "07"}-${day}T09:30:00-03:00`, actor: "ADMIN" }],
  };
});

export const mockRepairs: RepairOrder[] = [...featuredRepairs, ...generatedRepairs];

export const recentActivity = mockRepairs
  .flatMap((repair) =>
    repair.timeline.map((event) => ({
      ...event,
      repairId: repair.id,
      orderNumber: repair.orderNumber,
      device: `${repair.device.brand} ${repair.device.model}`,
    })),
  )
  .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))
  .slice(0, 6);
