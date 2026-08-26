import type { WeatherConditionKey } from "./types";

export interface WeatherCondition {
  key: WeatherConditionKey;
  label: string;
}

export function weatherConditionFromCode(code: number): WeatherCondition {
  if (code === 0) return { key: "clear", label: "Despejado" };
  if (code === 1) return { key: "partly-cloudy", label: "Mayormente despejado" };
  if (code === 2) return { key: "partly-cloudy", label: "Parcialmente nublado" };
  if (code === 3) return { key: "cloudy", label: "Nublado" };
  if (code === 45 || code === 48) return { key: "fog", label: "Niebla" };
  if ([51, 53, 55, 56, 57].includes(code)) return { key: "drizzle", label: "Llovizna" };
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return { key: "rain", label: "Lluvia" };
  if ([71, 73, 75, 77, 85, 86].includes(code)) return { key: "snow", label: "Nieve" };
  if ([95, 96, 99].includes(code)) return { key: "storm", label: "Tormenta" };
  return { key: "cloudy", label: "Condiciones variables" };
}
