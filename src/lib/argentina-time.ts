export const ARGENTINA_TIME_ZONE = "America/Argentina/Buenos_Aires";

function argentinaHour(date: Date): number {
  return Number(new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    hourCycle: "h23",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(date));
}

export function argentinaGreeting(date = new Date()): "Buenos días" | "Buenas tardes" | "Buenas noches" {
  const hour = argentinaHour(date);
  if (hour >= 5 && hour < 12) return "Buenos días";
  if (hour >= 12 && hour < 20) return "Buenas tardes";
  return "Buenas noches";
}

export function formatArgentinaDateTime(value: string | Date): string {
  return new Intl.DateTimeFormat("es-AR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(typeof value === "string" ? new Date(value) : value);
}

export function formatArgentinaLongDate(value: string | Date = new Date()): string {
  const formatted = new Intl.DateTimeFormat("es-AR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(typeof value === "string" ? new Date(value) : value);

  return formatted.charAt(0).toLocaleUpperCase("es-AR") + formatted.slice(1);
}

export function formatArgentinaTime(value: string | Date): string {
  return new Intl.DateTimeFormat("es-AR", {
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: ARGENTINA_TIME_ZONE,
  }).format(typeof value === "string" ? new Date(value) : value);
}
