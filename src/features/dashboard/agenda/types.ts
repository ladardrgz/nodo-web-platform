export const AGENDA_EVENT_TYPES = {
  REPAIR: "REPAIR",
  PICKUP: "PICKUP",
  DELIVERY: "DELIVERY",
  REMINDER: "REMINDER",
  GENERAL: "GENERAL",
} as const;

export type AgendaEventType = (typeof AGENDA_EVENT_TYPES)[keyof typeof AGENDA_EVENT_TYPES];

export interface AgendaEvent {
  /** Fecha civil YYYY-MM-DD interpretada en America/Argentina/Buenos_Aires. */
  date: string;
  description?: string;
  id: string;
  organizationId: string;
  referenceId?: string;
  /** Hora local HH:mm; null representa una actividad de día completo. */
  time: string | null;
  title: string;
  type: AgendaEventType;
}
