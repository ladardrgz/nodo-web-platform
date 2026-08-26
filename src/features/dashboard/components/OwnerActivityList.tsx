import { Activity, ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";

import { Card } from "@/components/ui/Card";
import { ownerActivityEntityLabel, ownerActivityLabel } from "@/features/dashboard/activity-labels";
import type { OwnerActivityPage } from "@/features/dashboard/types";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { formatArgentinaDateTime } from "@/lib/argentina-time";

function activityPageUrl(page: number): string {
  return `/dashboard?activityPage=${page}#activity`;
}

export function OwnerActivityList({ activity }: { activity: OwnerActivityPage }) {
  const start = activity.totalItems ? (activity.page - 1) * activity.pageSize + 1 : 0;
  const end = Math.min(activity.page * activity.pageSize, activity.totalItems);

  return (
    <Card className="h-full overflow-hidden" id="activity">
      <header className="flex items-start justify-between gap-4 border-b border-app-border px-5 py-4">
        <div>
          <div className="flex items-center gap-2"><h2 className="font-bold text-app-text">Actividad reciente</h2><ContextHelp label="Explicar la actividad reciente" title="¿Qué muestra Actividad reciente?">Resume los últimos cambios importantes ocurridos en tu organización para que puedas identificar rápidamente qué pasó y cuándo.</ContextHelp></div>
          <p className="mt-1 text-xs text-app-text-muted">Eventos de esta organización, del más reciente al más antiguo.</p>
        </div>
      </header>

      {activity.error ? (
        <div className="grid min-h-52 place-items-center p-6 text-center"><div><Activity aria-hidden="true" className="mx-auto size-8 text-app-text-muted" /><p className="mt-3 font-bold text-app-text">No pudimos cargar la actividad.</p><p className="mt-1 text-sm text-app-text-muted">El resto del dashboard continúa disponible.</p></div></div>
      ) : activity.events.length ? (
        <ol className="divide-y divide-app-border">
          {activity.events.map((event) => (
            <li className="flex gap-3 px-5 py-4" key={event.id}>
              <span aria-hidden="true" className="mt-1.5 size-2 shrink-0 rounded-full bg-accent" />
              <div className="min-w-0"><strong className="text-sm text-app-text">{ownerActivityLabel(event.eventType)}</strong><p className="mt-1 text-xs text-app-text-muted">{ownerActivityEntityLabel(event.entityType)} · {formatArgentinaDateTime(event.createdAt)}</p></div>
            </li>
          ))}
        </ol>
      ) : (
        <div className="grid min-h-52 place-items-center p-6 text-center"><div><Activity aria-hidden="true" className="mx-auto size-8 text-app-text-muted" /><p className="mt-3 font-bold text-app-text">Todavía no hay actividad registrada.</p><p className="mt-1 text-sm text-app-text-muted">Los cambios importantes de tu organización aparecerán aquí.</p></div></div>
      )}

      {!activity.error && activity.totalItems > 0 ? (
        <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-app-border px-5 py-4">
          <p aria-live="polite" className="text-xs text-app-text-muted">Mostrando {start}–{end} de {activity.totalItems} eventos</p>
          <nav aria-label="Paginación de actividad" className="flex items-center gap-2">
            <Link aria-disabled={activity.page <= 1} className={`inline-flex min-h-9 items-center gap-1 rounded-lg px-3 text-sm font-semibold text-app-text-secondary ring-1 ring-inset ring-app-border transition-colors ${activity.page <= 1 ? "pointer-events-none opacity-40" : "hover:bg-app-surface-soft hover:text-app-text"}`} href={activityPageUrl(Math.max(1, activity.page - 1))}><ChevronLeft aria-hidden="true" className="size-4" />Anterior</Link>
            <span className="min-w-12 text-center text-xs font-semibold text-app-text-muted">{activity.page} / {activity.totalPages}</span>
            <Link aria-disabled={activity.page >= activity.totalPages} className={`inline-flex min-h-9 items-center gap-1 rounded-lg px-3 text-sm font-semibold text-app-text-secondary ring-1 ring-inset ring-app-border transition-colors ${activity.page >= activity.totalPages ? "pointer-events-none opacity-40" : "hover:bg-app-surface-soft hover:text-app-text"}`} href={activityPageUrl(Math.min(activity.totalPages, activity.page + 1))}>Siguiente<ChevronRight aria-hidden="true" className="size-4" /></Link>
          </nav>
        </footer>
      ) : null}
    </Card>
  );
}
