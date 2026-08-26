import { WeatherCard } from "@/features/dashboard/weather/components/WeatherCard";
import { getWeatherForLocation } from "@/features/dashboard/weather/open-meteo-provider";
import type { WeatherLocation } from "@/features/dashboard/weather/types";

export async function OwnerWeather({ location }: { location: WeatherLocation | null }) {
  const result = await getWeatherForLocation(location);
  return <WeatherCard result={result} />;
}
