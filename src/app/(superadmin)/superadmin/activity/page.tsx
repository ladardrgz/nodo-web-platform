import { Activity, ChevronLeft, ChevronRight, Search } from "lucide-react";
import Link from "next/link";

import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { formatArgentinaDateTime } from "@/lib/argentina-time";
import { requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const PAGE_SIZE = 5;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
type Params = { page?: string; action?: string; actor?: string; organization?: string; result?: string; from?: string; to?: string };

function pageUrl(params: Params, page: number) {
  const query = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => { if (value && key !== "page") query.set(key, value); });
  query.set("page", String(page));
  return `/superadmin/activity?${query}`;
}

export default async function SuperadminActivityPage({ searchParams }: { searchParams: Promise<Params> }) {
  await requireRole(["SUPERADMIN"]);
  const params = await searchParams;
  const requestedPage = Number.parseInt(params.page ?? "1", 10);
  const page = Number.isFinite(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const supabase = await createSupabaseServerClient();
  let query = supabase.from("audit_events").select("id,event_type,entity_type,entity_id,organization_id,actor_user_id,result,created_at", { count: "exact" }).order("created_at", { ascending: false });
  const action = params.action?.trim().slice(0, 100);
  if (action) query = query.ilike("event_type", `%${action}%`);
  if (params.actor && uuidPattern.test(params.actor)) query = query.eq("actor_user_id", params.actor);
  if (params.organization && uuidPattern.test(params.organization)) query = query.eq("organization_id", params.organization);
  if (params.result === "SUCCESS" || params.result === "FAILURE") query = query.eq("result", params.result);
  if (params.from && /^\d{4}-\d{2}-\d{2}$/.test(params.from)) query = query.gte("created_at", `${params.from}T00:00:00-03:00`);
  if (params.to && /^\d{4}-\d{2}-\d{2}$/.test(params.to)) query = query.lte("created_at", `${params.to}T23:59:59.999-03:00`);
  const from = (page - 1) * PAGE_SIZE;
  const [{ data: events, count, error }, { data: organizations }, { data: actors }] = await Promise.all([
    query.range(from, from + PAGE_SIZE - 1),
    supabase.from("organizations").select("id,name").order("name"),
    supabase.from("profiles").select("id,display_name,first_name,last_name").order("display_name"),
  ]);
  const total = count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const organizationMap = new Map((organizations ?? []).map((item) => [item.id, item.name]));
  const actorMap = new Map((actors ?? []).map((item) => [item.id, item.display_name || [item.first_name, item.last_name].filter(Boolean).join(" ") || "Usuario"]));
  const start = total ? from + 1 : 0;
  const end = Math.min(from + PAGE_SIZE, total);

  return <div className="space-y-5"><header><div className="flex items-center gap-2"><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Auditoría</p><ContextHelp label="Ayuda sobre auditoría" title="¿Qué registra la auditoría?">Registra acciones administrativas relevantes con actor, entidad, fecha y resultado. Es append-only desde la aplicación y excluye contraseñas, tokens, cookies y secretos.</ContextHelp></div><h1 className="mt-1 text-2xl font-bold text-ink">Actividad administrativa</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-ink-muted">Consultá eventos paginados y filtrados desde la base de datos.</p></header><section className="rounded-xl border border-line bg-surface-raised"><form className="grid gap-3 border-b border-line p-4 md:grid-cols-2 xl:grid-cols-6" method="get"><label className="space-y-1 xl:col-span-2"><span className="text-xs font-bold text-ink-secondary">Acción</span><input className="field-control" defaultValue={params.action} name="action" placeholder="Ej: ORGANIZATION" /></label><label className="space-y-1"><span className="text-xs font-bold text-ink-secondary">Actor</span><select className="field-control" defaultValue={params.actor ?? ""} name="actor"><option value="">Todos</option>{(actors ?? []).map((actor) => <option key={actor.id} value={actor.id}>{actorMap.get(actor.id)}</option>)}</select></label><label className="space-y-1"><span className="text-xs font-bold text-ink-secondary">Organización</span><select className="field-control" defaultValue={params.organization ?? ""} name="organization"><option value="">Todas</option>{(organizations ?? []).map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select></label><label className="space-y-1"><span className="text-xs font-bold text-ink-secondary">Resultado</span><select className="field-control" defaultValue={params.result ?? ""} name="result"><option value="">Todos</option><option value="SUCCESS">Correcto</option><option value="FAILURE">Rechazado</option></select></label><div className="flex items-end"><button className="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-lg bg-accent px-4 text-sm font-semibold text-white hover:bg-accent-strong"><Search className="size-4" />Filtrar</button></div><label className="space-y-1"><span className="text-xs font-bold text-ink-secondary">Desde</span><input className="field-control" defaultValue={params.from} name="from" type="date" /></label><label className="space-y-1"><span className="text-xs font-bold text-ink-secondary">Hasta</span><input className="field-control" defaultValue={params.to} name="to" type="date" /></label></form>{error ? <p className="p-5 text-sm text-danger">No pudimos cargar la auditoría. Intentá nuevamente.</p> : events?.length ? <div className="divide-y divide-line">{events.map((event) => <article className="grid gap-2 px-5 py-4 md:grid-cols-[minmax(0,1fr)_180px_150px] md:items-center" key={event.id}><div><strong className="text-sm text-ink">{event.event_type.replaceAll("_", " ")}</strong><p className="mt-1 text-xs text-ink-muted">{event.entity_type || "SISTEMA"} · {organizationMap.get(event.organization_id ?? "") ?? "Global"}</p></div><div className="text-xs text-ink-secondary"><span className="block font-semibold">{actorMap.get(event.actor_user_id ?? "") ?? "Sistema"}</span><span>{formatArgentinaDateTime(event.created_at)}</span></div><span className={`w-fit rounded-full px-2.5 py-1 text-xs font-bold ${event.result === "FAILURE" ? "bg-danger-soft text-danger" : "bg-success-soft text-success"}`}>{event.result === "FAILURE" ? "Rechazado" : "Correcto"}</span></article>)}</div> : <div className="grid min-h-52 place-items-center p-5 text-center"><div><Activity className="mx-auto size-8 text-ink-muted" /><p className="mt-3 font-bold text-ink">No encontramos eventos con estos filtros.</p><Link className="mt-3 inline-block text-sm font-semibold text-accent" href="/superadmin/activity">Limpiar filtros</Link></div></div>}<footer className="flex flex-wrap items-center justify-between gap-3 border-t border-line px-5 py-4"><p className="text-xs text-ink-muted">Mostrando {start}–{end} de {total} eventos</p><nav aria-label="Paginación de auditoría" className="flex items-center gap-2"><Link aria-disabled={page <= 1} className={`inline-flex min-h-9 items-center gap-1 rounded-lg px-3 text-sm font-semibold ring-1 ring-inset ring-line ${page <= 1 ? "pointer-events-none opacity-40" : "hover:bg-surface-soft"}`} href={pageUrl(params, Math.max(1, page - 1))}><ChevronLeft className="size-4" />Anterior</Link><span className="px-2 text-sm font-semibold text-ink">{Math.min(page, totalPages)} / {totalPages}</span><Link aria-disabled={page >= totalPages} className={`inline-flex min-h-9 items-center gap-1 rounded-lg px-3 text-sm font-semibold ring-1 ring-inset ring-line ${page >= totalPages ? "pointer-events-none opacity-40" : "hover:bg-surface-soft"}`} href={pageUrl(params, Math.min(totalPages, page + 1))}>Siguiente<ChevronRight className="size-4" /></Link></nav></footer></section></div>;
}
