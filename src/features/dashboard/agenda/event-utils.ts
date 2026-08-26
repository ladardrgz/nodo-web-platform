import type { AgendaEvent } from "./types";

export function groupAgendaEvents(events: AgendaEvent[]): Map<string, AgendaEvent[]> {
  const grouped = new Map<string, AgendaEvent[]>();
  for (const event of events) {
    const list = grouped.get(event.date) ?? [];
    list.push(event);
    grouped.set(event.date, list);
  }
  for (const list of grouped.values()) {
    list.sort((left, right) => (left.time ?? "99:99").localeCompare(right.time ?? "99:99"));
  }
  return grouped;
}
