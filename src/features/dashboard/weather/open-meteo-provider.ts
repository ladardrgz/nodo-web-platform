import "server-only";

import {
  buildOpenMeteoForecastUrl,
  buildOpenMeteoGeocodingUrl,
  mapOpenMeteoForecast,
  resolveOpenMeteoCoordinates,
  type OpenMeteoForecastResponse,
  type OpenMeteoGeocodingResult,
} from "@/features/dashboard/weather/open-meteo-mapper";
import type { WeatherLocation, WeatherResult } from "@/features/dashboard/weather/types";

export const WEATHER_REVALIDATE_SECONDS = 1_200;
export const GEOCODING_REVALIDATE_SECONDS = 86_400;
const WEATHER_TIMEOUT_MS = 4_500;

async function readJson<T>(url: string, revalidate: number): Promise<T> {
  const response = await fetch(url, {
    next: { revalidate },
    signal: AbortSignal.timeout(WEATHER_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error("WEATHER_PROVIDER_RESPONSE");
  return response.json() as Promise<T>;
}

export async function getWeatherForLocation(location: WeatherLocation | null): Promise<WeatherResult> {
  if (!location?.locality || !location.province || !location.countryCode) return { status: "location-unavailable" };

  try {
    const geocoding = await readJson<{ results?: OpenMeteoGeocodingResult[] }>(buildOpenMeteoGeocodingUrl(location), GEOCODING_REVALIDATE_SECONDS);
    const coordinates = resolveOpenMeteoCoordinates(geocoding.results ?? [], location);
    if (!coordinates) return { status: "location-not-found" };

    const forecast = await readJson<OpenMeteoForecastResponse>(buildOpenMeteoForecastUrl(coordinates.latitude, coordinates.longitude), WEATHER_REVALIDATE_SECONDS);
    const data = mapOpenMeteoForecast(forecast, location);
    return data ? { status: "success", data } : { status: "provider-error" };
  } catch (error) {
    console.error("Error técnico del proveedor meteorológico:", error instanceof Error ? error.name : "UNKNOWN");
    return { status: "provider-error" };
  }
}
