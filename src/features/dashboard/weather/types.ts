export interface WeatherLocation {
  countryCode: string;
  countryName: string;
  locality: string;
  province: string;
}

export type WeatherConditionKey = "clear" | "partly-cloudy" | "cloudy" | "fog" | "drizzle" | "rain" | "snow" | "storm";

export interface WeatherData {
  apparentTemperature: number;
  condition: string;
  conditionKey: WeatherConditionKey;
  humidity: number;
  isDay: boolean;
  location: string;
  maxTemperature: number;
  minTemperature: number;
  precipitationProbability: number;
  provider: "OPEN_METEO";
  temperature: number;
  updatedAt: string;
  weatherCode: number;
  windSpeed: number;
}

export type WeatherResult =
  | { status: "success"; data: WeatherData }
  | { status: "location-unavailable" }
  | { status: "location-not-found" }
  | { status: "provider-error" };
