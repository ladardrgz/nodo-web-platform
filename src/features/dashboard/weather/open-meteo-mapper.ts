import { ARGENTINA_TIME_ZONE } from "../../../lib/argentina-time";
import { weatherConditionFromCode } from "./conditions";
import type { WeatherData, WeatherLocation } from "./types";

export interface OpenMeteoGeocodingResult {
  admin1?: string;
  country_code?: string;
  latitude?: number;
  longitude?: number;
  name?: string;
}

export interface OpenMeteoForecastResponse {
  current?: {
    apparent_temperature?: number;
    is_day?: number;
    relative_humidity_2m?: number;
    temperature_2m?: number;
    time?: number;
    weather_code?: number;
    wind_speed_10m?: number;
  };
  daily?: {
    precipitation_probability_max?: number[];
    temperature_2m_max?: number[];
    temperature_2m_min?: number[];
  };
}

function normalized(value: string | undefined): string {
  return (value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLocaleLowerCase("es-AR");
}

function finite(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function buildOpenMeteoGeocodingUrl(location: WeatherLocation): string {
  const url = new URL("https://geocoding-api.open-meteo.com/v1/search");
  url.searchParams.set("name", `${location.locality}, ${location.province}`);
  url.searchParams.set("count", "10");
  url.searchParams.set("language", "es");
  url.searchParams.set("format", "json");
  url.searchParams.set("countryCode", location.countryCode.toUpperCase());
  return url.toString();
}

export function resolveOpenMeteoCoordinates(results: OpenMeteoGeocodingResult[], location: WeatherLocation): { latitude: number; longitude: number } | null {
  const candidates = results.filter((result) =>
    finite(result.latitude)
    && finite(result.longitude)
    && normalized(result.country_code) === normalized(location.countryCode),
  );
  const exact = candidates.find((result) => normalized(result.name) === normalized(location.locality) && normalized(result.admin1) === normalized(location.province));
  const sameProvince = candidates.find((result) => normalized(result.admin1) === normalized(location.province));
  const selected = exact ?? sameProvince ?? null;
  return selected ? { latitude: selected.latitude!, longitude: selected.longitude! } : null;
}

export function buildOpenMeteoForecastUrl(latitude: number, longitude: number): string {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", String(latitude));
  url.searchParams.set("longitude", String(longitude));
  url.searchParams.set("current", "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m");
  url.searchParams.set("daily", "temperature_2m_max,temperature_2m_min,precipitation_probability_max");
  url.searchParams.set("temperature_unit", "celsius");
  url.searchParams.set("wind_speed_unit", "kmh");
  url.searchParams.set("precipitation_unit", "mm");
  url.searchParams.set("timezone", ARGENTINA_TIME_ZONE);
  url.searchParams.set("forecast_days", "1");
  url.searchParams.set("timeformat", "unixtime");
  return url.toString();
}

export function mapOpenMeteoForecast(response: OpenMeteoForecastResponse, location: WeatherLocation): WeatherData | null {
  const current = response.current;
  const daily = response.daily;
  const maxTemperature = daily?.temperature_2m_max?.[0];
  const minTemperature = daily?.temperature_2m_min?.[0];
  const precipitationProbability = daily?.precipitation_probability_max?.[0];
  if (!current
    || !finite(current.temperature_2m)
    || !finite(current.apparent_temperature)
    || !finite(current.relative_humidity_2m)
    || !finite(current.wind_speed_10m)
    || !finite(current.weather_code)
    || !finite(current.is_day)
    || !finite(current.time)
    || !finite(maxTemperature)
    || !finite(minTemperature)
    || !finite(precipitationProbability)) return null;

  const condition = weatherConditionFromCode(current.weather_code);
  return {
    apparentTemperature: current.apparent_temperature,
    condition: condition.label,
    conditionKey: condition.key,
    humidity: current.relative_humidity_2m,
    isDay: current.is_day === 1,
    location: `${location.locality}, ${location.province}`,
    maxTemperature,
    minTemperature,
    precipitationProbability,
    provider: "OPEN_METEO",
    temperature: current.temperature_2m,
    updatedAt: new Date(current.time * 1000).toISOString(),
    weatherCode: current.weather_code,
    windSpeed: current.wind_speed_10m,
  };
}
