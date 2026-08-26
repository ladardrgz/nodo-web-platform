import "server-only";

import { buildDevelopmentAgendaEvents } from "@/features/dashboard/agenda/development-events";
import type { AgendaEvent } from "@/features/dashboard/agenda/types";
import { isDemoDataEnabled } from "@/lib/demo";

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
  // Punto único de reemplazo: la persistencia futura consultará un rango completo
  // y derivará organizationId de la sesión, nunca desde parámetros del navegador.
  if (!isDemoDataEnabled()) return [];

  return buildDevelopmentAgendaEvents(organizationId, todayKey)
    .filter((event) => event.organizationId === organizationId && event.date >= start && event.date <= end)
    .sort((left, right) => left.date.localeCompare(right.date) || (left.time ?? "99:99").localeCompare(right.time ?? "99:99"));
}
