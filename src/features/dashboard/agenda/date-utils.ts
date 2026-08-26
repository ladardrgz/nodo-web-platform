import { ARGENTINA_TIME_ZONE } from "../../../lib/argentina-time";

export interface CalendarDay {
  dateKey: string;
  dayNumber: number;
  inCurrentMonth: boolean;
  isToday: boolean;
}

const DATE_KEY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

export function parseDateKey(dateKey: string): { day: number; monthIndex: number; year: number } {
  const match = DATE_KEY_PATTERN.exec(dateKey);
  if (!match) throw new Error("INVALID_DATE_KEY");
  const year = Number(match[1]);
  const monthIndex = Number(match[2]) - 1;
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, monthIndex, day, 12));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== monthIndex || date.getUTCDate() !== day) {
    throw new Error("INVALID_DATE_KEY");
  }
  return { day, monthIndex, year };
}

export function dateKeyFromParts(year: number, monthIndex: number, day: number): string {
  const date = new Date(Date.UTC(year, monthIndex, day, 12));
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

export function argentinaDateKey(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    timeZone: ARGENTINA_TIME_ZONE,
  }).formatToParts(date);
  const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

export function addCivilDays(dateKey: string, amount: number): string {
  const { day, monthIndex, year } = parseDateKey(dateKey);
  return dateKeyFromParts(year, monthIndex, day + amount);
}

export function shiftCalendarMonth(year: number, monthIndex: number, change: number): { monthIndex: number; year: number } {
  const date = new Date(Date.UTC(year, monthIndex + change, 1, 12));
  return { monthIndex: date.getUTCMonth(), year: date.getUTCFullYear() };
}

function civilDate(dateKey: string): Date {
  const { day, monthIndex, year } = parseDateKey(dateKey);
  return new Date(Date.UTC(year, monthIndex, day, 12));
}

export function formatMonthLabel(year: number, monthIndex: number): string {
  const label = new Intl.DateTimeFormat("es-AR", {
    month: "long",
    year: "numeric",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(new Date(Date.UTC(year, monthIndex, 15, 12)));
  return label.charAt(0).toLocaleUpperCase("es-AR") + label.slice(1);
}

export function formatCalendarAriaLabel(dateKey: string, eventCount: number): string {
  const date = new Intl.DateTimeFormat("es-AR", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(civilDate(dateKey));
  const events = eventCount === 1 ? "1 evento" : `${eventCount} eventos`;
  return `${date}, ${events}`;
}

export function formatAgendaDateLabel(dateKey: string): string {
  return new Intl.DateTimeFormat("es-AR", {
    day: "numeric",
    month: "long",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(civilDate(dateKey));
}

export function buildCalendarMonth(year: number, monthIndex: number, todayKey: string): CalendarDay[] {
  const first = new Date(Date.UTC(year, monthIndex, 1, 12));
  const mondayOffset = (first.getUTCDay() + 6) % 7;
  const daysInMonth = new Date(Date.UTC(year, monthIndex + 1, 0, 12)).getUTCDate();
  const cellCount = Math.ceil((mondayOffset + daysInMonth) / 7) * 7;
  return Array.from({ length: cellCount }, (_, index) => {
    const dateKey = dateKeyFromParts(year, monthIndex, index - mondayOffset + 1);
    const parts = parseDateKey(dateKey);
    return {
      dateKey,
      dayNumber: parts.day,
      inCurrentMonth: parts.year === year && parts.monthIndex === monthIndex,
      isToday: dateKey === todayKey,
    };
  });
}

export function agendaWindowRange(todayKey: string): { end: string; start: string } {
  const { monthIndex, year } = parseDateKey(todayKey);
  return {
    start: dateKeyFromParts(year, monthIndex - 1, 1),
    end: dateKeyFromParts(year, monthIndex + 2, 0),
  };
}
