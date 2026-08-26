"use client";

import { Bell, CalendarClock, ChevronLeft, ChevronRight, CircleDot, PackageCheck, Truck, Wrench } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";

import {
  addCivilDays,
  argentinaDateKey,
  buildCalendarMonth,
  formatAgendaDateLabel,
  formatCalendarAriaLabel,
  formatMonthLabel,
  parseDateKey,
  shiftCalendarMonth,
} from "@/features/dashboard/agenda/date-utils";
import { groupAgendaEvents } from "@/features/dashboard/agenda/event-utils";
import { AGENDA_EVENT_TYPES, type AgendaEvent, type AgendaEventType } from "@/features/dashboard/agenda/types";
import { cn } from "@/lib/cn";

const WEEKDAYS = [
  { compact: "L", full: "lunes" },
  { compact: "M", full: "martes" },
  { compact: "X", full: "miércoles" },
  { compact: "J", full: "jueves" },
  { compact: "V", full: "viernes" },
  { compact: "S", full: "sábado" },
  { compact: "D", full: "domingo" },
];

const EVENT_TYPES: Record<AgendaEventType, { icon: LucideIcon; label: string }> = {
  [AGENDA_EVENT_TYPES.REPAIR]: { icon: Wrench, label: "Reparación" },
  [AGENDA_EVENT_TYPES.PICKUP]: { icon: PackageCheck, label: "Retiro" },
  [AGENDA_EVENT_TYPES.DELIVERY]: { icon: Truck, label: "Entrega" },
  [AGENDA_EVENT_TYPES.REMINDER]: { icon: Bell, label: "Recordatorio" },
  [AGENDA_EVENT_TYPES.GENERAL]: { icon: CircleDot, label: "General" },
};

export function AgendaCalendar({ events, initialTodayKey }: { events: AgendaEvent[]; initialTodayKey: string }) {
  const initial = parseDateKey(initialTodayKey);
  const [todayKey, setTodayKey] = useState(initialTodayKey);
  const [selectedDate, setSelectedDate] = useState(initialTodayKey);
  const [visibleMonth, setVisibleMonth] = useState({ monthIndex: initial.monthIndex, year: initial.year });
  const calendarRef = useRef<HTMLDivElement>(null);
  const pendingFocusRef = useRef<string | null>(null);

  useEffect(() => {
    const updateToday = () => {
      const nextToday = argentinaDateKey();
      setTodayKey((previous) => {
        if (previous !== nextToday) setSelectedDate((selected) => selected === previous ? nextToday : selected);
        return nextToday;
      });
    };
    const timer = window.setInterval(updateToday, 60_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    const focusDate = pendingFocusRef.current;
    if (!focusDate) return;
    calendarRef.current?.querySelector<HTMLButtonElement>(`button[data-date="${focusDate}"]`)?.focus();
    pendingFocusRef.current = null;
  }, [visibleMonth]);

  const eventsByDate = useMemo(() => groupAgendaEvents(events), [events]);
  const days = useMemo(() => buildCalendarMonth(visibleMonth.year, visibleMonth.monthIndex, todayKey), [todayKey, visibleMonth]);
  const selectedEvents = eventsByDate.get(selectedDate) ?? [];

  const selectAndReveal = (dateKey: string, focus = false) => {
    const parts = parseDateKey(dateKey);
    setSelectedDate(dateKey);
    setVisibleMonth({ monthIndex: parts.monthIndex, year: parts.year });
    if (focus) pendingFocusRef.current = dateKey;
  };

  const changeMonth = (change: number) => {
    const next = shiftCalendarMonth(visibleMonth.year, visibleMonth.monthIndex, change);
    setVisibleMonth(next);
    setSelectedDate(`${next.year}-${String(next.monthIndex + 1).padStart(2, "0")}-01`);
  };

  const handleDayKeyDown = (event: KeyboardEvent<HTMLButtonElement>, dateKey: string) => {
    const changes: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };
    const change = changes[event.key];
    if (change === undefined) return;
    event.preventDefault();
    selectAndReveal(addCivilDays(dateKey, change), true);
  };

  return (
    <div className="grid min-w-0 gap-5 lg:grid-cols-[minmax(320px,0.9fr)_minmax(280px,1.1fr)]">
      <section aria-label="Calendario mensual" className="min-w-0 rounded-xl border border-app-border bg-app-surface p-3 sm:p-4">
        <header className="mb-4 flex flex-wrap items-center justify-between gap-2">
          <h3 aria-live="polite" className="font-bold text-app-text">{formatMonthLabel(visibleMonth.year, visibleMonth.monthIndex)}</h3>
          <div className="flex items-center gap-1">
            <button aria-label="Mes anterior" className="grid size-9 place-items-center rounded-lg text-app-text-secondary transition-colors hover:bg-app-surface-soft hover:text-app-text focus-visible:outline-accent" onClick={() => changeMonth(-1)} title="Mes anterior" type="button"><ChevronLeft aria-hidden="true" className="size-4" /></button>
            <button className="min-h-9 rounded-lg px-3 text-xs font-bold text-accent transition-colors hover:bg-accent-soft focus-visible:outline-accent" onClick={() => selectAndReveal(todayKey)} type="button">Hoy</button>
            <button aria-label="Mes siguiente" className="grid size-9 place-items-center rounded-lg text-app-text-secondary transition-colors hover:bg-app-surface-soft hover:text-app-text focus-visible:outline-accent" onClick={() => changeMonth(1)} title="Mes siguiente" type="button"><ChevronRight aria-hidden="true" className="size-4" /></button>
          </div>
        </header>

        <div className="grid grid-cols-7">
          {WEEKDAYS.map((weekday) => <div aria-label={weekday.full} className="pb-2 text-center text-[11px] font-bold uppercase text-app-text-muted" key={weekday.full}><span aria-hidden="true">{weekday.compact}</span></div>)}
        </div>
        <div className="grid grid-cols-7 gap-1" ref={calendarRef}>
          {days.map((day) => {
            const count = eventsByDate.get(day.dateKey)?.length ?? 0;
            const selected = selectedDate === day.dateKey;
            return (
              <button
                aria-current={day.isToday ? "date" : undefined}
                aria-label={formatCalendarAriaLabel(day.dateKey, count)}
                aria-pressed={selected}
                className={cn(
                  "relative grid aspect-square min-h-9 place-items-center rounded-lg text-sm font-semibold transition-colors focus-visible:outline-accent",
                  day.inCurrentMonth ? "text-app-text" : "text-app-text-muted opacity-45",
                  !selected && "hover:bg-app-surface-soft",
                  day.isToday && !selected && "ring-1 ring-inset ring-accent text-accent",
                  selected && "bg-accent-button text-white shadow-sm hover:bg-accent-button-hover",
                )}
                data-date={day.dateKey}
                key={day.dateKey}
                onClick={() => selectAndReveal(day.dateKey)}
                onKeyDown={(event) => handleDayKeyDown(event, day.dateKey)}
                type="button"
              >
                {day.dayNumber}
                {count ? <span aria-hidden="true" className={cn("absolute bottom-1 size-1 rounded-full", selected ? "bg-white" : "bg-accent")} /> : null}
              </button>
            );
          })}
        </div>
      </section>

      <section aria-labelledby="selected-agenda-title" className="min-w-0 rounded-xl border border-app-border bg-app-surface p-4 sm:p-5">
        <div className="flex items-center gap-3"><span className="grid size-9 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><CalendarClock aria-hidden="true" className="size-4.5" /></span><div><p className="text-xs font-bold uppercase tracking-[0.12em] text-app-text-muted">Día seleccionado</p><h3 className="mt-0.5 font-bold text-app-text" id="selected-agenda-title">Agenda del {formatAgendaDateLabel(selectedDate)}</h3></div></div>
        {selectedEvents.length ? (
          <ol className="mt-4 divide-y divide-app-border">
            {selectedEvents.map((agendaEvent) => {
              const definition = EVENT_TYPES[agendaEvent.type];
              const Icon = definition.icon;
              return <li className="flex gap-3 py-3 first:pt-0 last:pb-0" key={agendaEvent.id}><span className="grid size-8 shrink-0 place-items-center rounded-lg bg-app-surface-soft text-accent"><Icon aria-hidden="true" className="size-4" /></span><div className="min-w-0"><div className="flex flex-wrap items-baseline gap-x-2 gap-y-1"><time className="text-xs font-bold tabular-nums text-accent">{agendaEvent.time || "Durante el día"}</time><span className="text-[11px] font-semibold text-app-text-muted">{definition.label}</span></div><p className="mt-1 text-sm font-semibold text-app-text">{agendaEvent.title}</p>{agendaEvent.description ? <p className="mt-1 text-xs leading-5 text-app-text-muted">{agendaEvent.description}</p> : null}</div></li>;
            })}
          </ol>
        ) : (
          <div className="grid min-h-40 place-items-center text-center"><div><CalendarClock aria-hidden="true" className="mx-auto size-7 text-app-text-muted" /><p className="mt-3 text-sm font-semibold text-app-text">No hay actividades programadas para este día.</p></div></div>
        )}
      </section>
    </div>
  );
}
