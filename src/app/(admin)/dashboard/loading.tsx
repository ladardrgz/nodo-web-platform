export default function DashboardLoading() {
  return (
    <div aria-label="Cargando dashboard" aria-live="polite" className="space-y-6" role="status">
      <div className="h-32 animate-pulse rounded-2xl border border-app-border bg-app-card sm:h-36" />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        {Array.from({ length: 5 }, (_, index) => <div className="h-28 animate-pulse rounded-xl border border-app-border bg-app-card" key={index} />)}
      </div>
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.7fr)_minmax(270px,0.6fr)]"><div className="h-96 animate-pulse rounded-xl border border-app-border bg-app-card" /><div className="h-80 animate-pulse rounded-xl border border-app-border bg-app-card" /></div>
      <div className="grid gap-5 xl:grid-cols-2"><div className="h-80 animate-pulse rounded-xl border border-app-border bg-app-card" /><div className="h-80 animate-pulse rounded-xl border border-app-border bg-app-card" /></div>
      <span className="sr-only">Cargando información de la organización…</span>
    </div>
  );
}
