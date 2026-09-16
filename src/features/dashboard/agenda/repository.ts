import "server-only";

import type { AgendaEvent } from "@/features/dashboard/agenda/types";

export async function listAgendaEventsForRange({
  end,
  organizationId,
  start,
  todayKey,
}: {
  end: string;
  organizationId: string;
  start: string;
  todayKey: string;
}): Promise<AgendaEvent[]> {
  // No hay todavía un contrato persistido de agenda en el esquema vigente.
  // La pantalla representa correctamente ese estado vacío, sin inventar turnos.
  void end;
  void organizationId;
  void start;
  void todayKey;
  return [];
}
