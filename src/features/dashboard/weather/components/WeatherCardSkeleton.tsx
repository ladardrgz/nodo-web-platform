export function WeatherCardSkeleton() {
  return <div aria-label="Cargando clima" className="h-full min-h-64 animate-pulse rounded-xl border border-app-border bg-app-surface p-5" role="status"><div className="h-5 w-20 rounded bg-app-surface-soft" /><div className="mt-6 h-16 w-28 rounded-xl bg-app-surface-soft" /><div className="mt-6 grid grid-cols-2 gap-2">{Array.from({ length: 5 }, (_, index) => <div className={`h-16 rounded-lg bg-app-surface-soft ${index === 4 ? "col-span-2" : ""}`} key={index} />)}</div><span className="sr-only">Consultando condiciones meteorológicas…</span></div>;
}
