import { CalendarDays, MapPin } from "lucide-react";
import type { ReactNode } from "react";

import { AgendaCalendar } from "@/features/dashboard/agenda/AgendaCalendar";
import type { AgendaEvent } from "@/features/dashboard/agenda/types";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";

export function TodayPanel({ dateLabel, events, locationLabel, todayKey, weather }: { dateLabel: string; events: AgendaEvent[]; locationLabel: string | null; todayKey: string; weather: ReactNode }) {
  return (
    <section aria-labelledby="today-panel-title">
      <header className="flex flex-wrap items-start justify-between gap-4 pb-4">
        <div><p className="text-xs font-bold uppercase tracking-[0.14em] text-accent">Hoy</p><div className="mt-1 flex items-center gap-2"><h2 className="text-lg font-bold text-app-text" id="today-panel-title">Agenda y clima</h2><ContextHelp label="Explicar la agenda" title="¿Para qué sirve la agenda?">Te permite visualizar actividades y fechas importantes de tu organización para organizar recepciones, entregas, retiros y recordatorios desde Nodo.</ContextHelp></div></div>
        <dl className="grid gap-3 sm:grid-cols-2">
          <div className="flex gap-3"><span className="grid size-9 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><CalendarDays aria-hidden="true" className="size-4.5" /></span><div><dt className="text-xs font-semibold text-app-text-muted">Fecha</dt><dd className="mt-1 text-sm font-semibold text-app-text">{dateLabel}</dd></div></div>
          <div className="flex gap-3"><span className="grid size-9 shrink-0 place-items-center rounded-lg bg-app-surface-soft text-app-text-secondary"><MapPin aria-hidden="true" className="size-4.5" /></span><div><dt className="text-xs font-semibold text-app-text-muted">Ubicación principal</dt><dd className="mt-1 text-sm font-semibold text-app-text">{locationLabel || "Ubicación no disponible"}</dd></div></div>
        </dl>
      </header>
      <div className="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1.7fr)_minmax(270px,0.6fr)]"><AgendaCalendar events={events} initialTodayKey={todayKey} /><div className="min-w-0">{weather}</div></div>
    </section>
  );
}
