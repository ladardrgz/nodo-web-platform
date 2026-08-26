"use client";

import { History } from "lucide-react";
import { useState } from "react";

import { Pagination } from "@/components/ui/Pagination";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { pageRange, paginate, SUPERADMIN_PAGE_SIZE } from "@/features/superadmin/list-utils";
import { formatArgentinaDateTime } from "@/lib/argentina-time";

export type SecurityEvent = { id: string; eventType: string; createdAt: string; result: string };

export function SecurityHistory({ events }: { events: SecurityEvent[] }) {
  const [page, setPage] = useState(1);
  const visible = paginate(events, page);
  const range = pageRange(page, events.length);
  return <section className="overflow-hidden rounded-xl border border-line bg-surface-raised"><div className="border-b border-line px-5 py-4"><div className="flex items-center gap-2"><h2 className="font-bold text-ink">Historial de seguridad</h2><ContextHelp label="Ayuda sobre el historial de seguridad" title="¿Qué muestra el historial de seguridad?">Permite revisar eventos relevantes relacionados con el acceso y la protección de tu cuenta. Nunca almacena contraseñas, tokens, cookies ni secretos MFA.</ContextHelp></div><p className="mt-1 text-xs text-ink-muted">Más reciente primero.</p></div>{visible.length ? <ol className="divide-y divide-line">{visible.map((event) => <li className="flex items-start gap-3 px-5 py-4" key={event.id}><span className="mt-1 grid size-8 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><History className="size-4" /></span><div className="min-w-0"><strong className="block text-sm text-ink">{event.eventType.replaceAll("_", " ")}</strong><p className="mt-1 text-xs text-ink-muted">{formatArgentinaDateTime(event.createdAt)} · {event.result === "FAILURE" ? "Rechazado" : "Correcto"}</p></div></li>)}</ol> : <p className="px-5 py-10 text-center text-sm text-ink-muted">Todavía no hay eventos de seguridad registrados.</p>}{events.length ? <div className="space-y-3 border-t border-line px-5 py-4"><p className="text-xs text-ink-muted">Mostrando {range.start}–{range.end} de {events.length} eventos</p><Pagination onPageChange={setPage} page={page} pageSize={SUPERADMIN_PAGE_SIZE} totalItems={events.length} /></div> : null}</section>;
}
