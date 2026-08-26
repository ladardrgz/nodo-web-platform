import { Cloud, CloudDrizzle, CloudFog, CloudLightning, CloudRain, CloudSnow, Droplets, Gauge, MapPin, Moon, Sun, Thermometer, Wind } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";

import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { formatArgentinaTime } from "@/lib/argentina-time";
import type { WeatherConditionKey, WeatherData, WeatherResult } from "@/features/dashboard/weather/types";

function ConditionIcon({ condition, isDay }: { condition: WeatherConditionKey; isDay: boolean }) {
  const className = "size-10";
  if (condition === "clear") return isDay ? <Sun aria-hidden="true" className={`${className} text-warning`} /> : <Moon aria-hidden="true" className={`${className} text-accent`} />;
  if (condition === "fog") return <CloudFog aria-hidden="true" className={`${className} text-app-text-muted`} />;
  if (condition === "drizzle") return <CloudDrizzle aria-hidden="true" className={`${className} text-accent`} />;
  if (condition === "rain") return <CloudRain aria-hidden="true" className={`${className} text-accent`} />;
  if (condition === "snow") return <CloudSnow aria-hidden="true" className={`${className} text-app-text-secondary`} />;
  if (condition === "storm") return <CloudLightning aria-hidden="true" className={`${className} text-warning`} />;
  return <Cloud aria-hidden="true" className={`${className} text-app-text-muted`} />;
}

function WeatherMetric({ className = "", icon, label, value }: { className?: string; icon: ReactNode; label: string; value: string }) {
  return <div className={`rounded-lg bg-app-surface-soft p-3 ${className}`}><dt className="flex items-center gap-1.5 text-[11px] font-semibold text-app-text-muted">{icon}{label}</dt><dd className="mt-1 text-sm font-bold text-app-text">{value}</dd></div>;
}

function WeatherDataCard({ data }: { data: WeatherData }) {
  return (
    <>
      <div className="mt-5 flex items-start justify-between gap-4">
        <div><p className="text-4xl font-bold tracking-tight text-app-text">{Math.round(data.temperature)}°</p><p className="mt-1 text-sm font-semibold text-app-text">{data.condition}</p><p className="mt-1 flex items-center gap-1.5 text-xs text-app-text-muted"><MapPin aria-hidden="true" className="size-3.5" />{data.location}</p></div>
        <span className="grid size-16 shrink-0 place-items-center rounded-2xl border border-app-border bg-app-surface-soft"><ConditionIcon condition={data.conditionKey} isDay={data.isDay} /></span>
      </div>
      <dl className="mt-5 grid grid-cols-2 gap-2">
        <WeatherMetric icon={<Thermometer aria-hidden="true" className="size-3.5" />} label="Sensación" value={`${Math.round(data.apparentTemperature)} °C`} />
        <WeatherMetric icon={<Droplets aria-hidden="true" className="size-3.5" />} label="Humedad" value={`${Math.round(data.humidity)} %`} />
        <WeatherMetric icon={<Wind aria-hidden="true" className="size-3.5" />} label="Viento" value={`${Math.round(data.windSpeed)} km/h`} />
        <WeatherMetric icon={<CloudRain aria-hidden="true" className="size-3.5" />} label="Lluvia" value={`${Math.round(data.precipitationProbability)} %`} />
        <WeatherMetric className="col-span-2" icon={<Gauge aria-hidden="true" className="size-3.5" />} label="Mín. / Máx." value={`${Math.round(data.minTemperature)}° / ${Math.round(data.maxTemperature)}°`} />
      </dl>
      <div className="mt-4 flex flex-wrap items-center justify-between gap-2 text-[11px] text-app-text-muted">
        <span>Actualizado {formatArgentinaTime(data.updatedAt)}</span>
        <span>
          Clima: <a className="font-semibold text-accent hover:underline" href="https://open-meteo.com/" rel="noopener noreferrer" target="_blank">Open-Meteo</a>
          {" · "}
          Ubicación: <a className="font-semibold text-accent hover:underline" href="https://www.geonames.org/" rel="noopener noreferrer" target="_blank">GeoNames</a>
        </span>
      </div>
    </>
  );
}

export function WeatherCard({ result }: { result: WeatherResult }) {
  return (
    <section aria-labelledby="weather-card-title" className="h-full rounded-xl border border-app-border bg-app-surface p-4 sm:p-5">
      <div className="flex items-center gap-2"><h3 className="font-bold text-app-text" id="weather-card-title">Clima</h3><ContextHelp label="Explicar el clima" title="¿Por qué aparece el clima?"><span>Nodo utiliza la ubicación configurada de tu organización para mostrar las condiciones meteorológicas de tu zona. Esta información puede ayudarte a organizar entregas, retiros o visitas.</span><span className="mt-3 block">Nodo no utiliza la ubicación actual de tu dispositivo para esta función.</span></ContextHelp></div>
      {result.status === "success" ? <WeatherDataCard data={result.data} /> : (
        <div className="grid min-h-64 place-items-center text-center"><div><Cloud aria-hidden="true" className="mx-auto size-9 text-app-text-muted" /><p className="mt-3 text-sm font-semibold text-app-text">{result.status === "provider-error" ? "No pudimos obtener el clima en este momento." : "No pudimos identificar la ubicación para mostrar el clima."}</p>{result.status !== "provider-error" ? <Link className="mt-3 inline-flex min-h-9 items-center rounded-lg px-3 text-sm font-semibold text-accent hover:bg-accent-soft" href="/organization-settings">Revisar ubicación</Link> : <p className="mt-2 text-xs text-app-text-muted">El resto del dashboard continúa disponible.</p>}</div></div>
      )}
    </section>
  );
}
