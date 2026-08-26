import { addCivilDays } from "@/features/dashboard/agenda/date-utils";
import { AGENDA_EVENT_TYPES, type AgendaEvent } from "@/features/dashboard/agenda/types";

export function buildDevelopmentAgendaEvents(organizationId: string, todayKey: string): AgendaEvent[] {
  return [
    { id: "demo-agenda-1", organizationId, date: todayKey, time: "09:30", type: AGENDA_EVENT_TYPES.REPAIR, title: "Recepción Samsung Galaxy A14", description: "Ingreso programado de equipo." },
    { id: "demo-agenda-2", organizationId, date: todayKey, time: "11:00", type: AGENDA_EVENT_TYPES.PICKUP, title: "Retiro iPhone 13" },
    { id: "demo-agenda-3", organizationId, date: todayKey, time: "16:30", type: AGENDA_EVENT_TYPES.REMINDER, title: "Revisar presupuesto Lenovo IdeaPad" },
    { id: "demo-agenda-4", organizationId, date: addCivilDays(todayKey, 2), time: null, type: AGENDA_EVENT_TYPES.GENERAL, title: "Ordenar pendientes de la semana" },
    { id: "demo-agenda-5", organizationId, date: addCivilDays(todayKey, 4), time: "10:00", type: AGENDA_EVENT_TYPES.DELIVERY, title: "Entrega Motorola Moto G54" },
  ];
}
