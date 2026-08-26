"use client";

import { Building2, ChevronRight, Search, X } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";

import { IconInput } from "@/components/ui/IconInput";
import { Pagination } from "@/components/ui/Pagination";
import { pageRange, paginate, SUPERADMIN_PAGE_SIZE } from "@/features/superadmin/list-utils";
import type { OrganizationListItem } from "@/features/superadmin/types";

type StatusFilter = "ALL" | "ACTIVE" | "SUSPENDED";

export function OrganizationsList({ organizations }: { organizations: OrganizationListItem[] }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<StatusFilter>("ALL");
  const [page, setPage] = useState(1);
  const filtered = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase("es");
    return organizations.filter((organization) => (status === "ALL" || organization.status === status) && (!normalizedQuery || `${organization.name} ${organization.slug}`.toLocaleLowerCase("es").includes(normalizedQuery)));
  }, [organizations, query, status]);
  const visible = paginate(filtered, page);
  const range = pageRange(page, filtered.length);
  const clear = () => { setQuery(""); setStatus("ALL"); setPage(1); };

  return <div><div className="grid gap-3 border-b border-line p-4 sm:grid-cols-[minmax(0,1fr)_180px] sm:p-5"><label><span className="sr-only">Buscar organizaciones</span><IconInput aria-label="Buscar organizaciones" clearLabel="Limpiar búsqueda de organizaciones" leadingIcon={<Search className="size-4" />} onChange={(event) => { setQuery(event.target.value); setPage(1); }} onClear={() => { setQuery(""); setPage(1); }} placeholder="Buscar por nombre o identificador" type="search" value={query} /></label><label><span className="sr-only">Filtrar organizaciones por estado</span><select className="field-control" onChange={(event) => { setStatus(event.target.value as StatusFilter); setPage(1); }} value={status}><option value="ALL">Todas</option><option value="ACTIVE">Activas</option><option value="SUSPENDED">Suspendidas</option></select></label></div>{visible.length ? <div className="divide-y divide-line">{visible.map((organization) => <article className="flex items-center justify-between gap-4 px-4 py-4 sm:px-5" key={organization.id}><div className="flex min-w-0 items-center gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><Building2 className="size-5" /></span><div className="min-w-0">{organization.isDevelopmentMock ? <strong className="block truncate text-sm text-ink">{organization.name}</strong> : <Link className="group inline-flex max-w-full items-center gap-1 font-bold text-ink hover:text-accent" href={`/superadmin/organizations/${organization.id}`}><span className="truncate">{organization.name}</span><ChevronRight className="size-4 shrink-0 transition-transform group-hover:translate-x-0.5" /></Link>}<p className="mt-0.5 truncate font-mono text-xs text-ink-muted">{organization.slug}</p>{organization.isDevelopmentMock ? <span className="mt-1 block text-[10px] font-bold uppercase tracking-wide text-warning">Dato de desarrollo</span> : null}</div></div><span className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold ring-1 ring-inset ${organization.status === "ACTIVE" ? "bg-success-soft text-success ring-success/20" : "bg-danger-soft text-danger ring-danger/20"}`}><span aria-hidden className="size-1.5 rounded-full bg-current" />{organization.status === "ACTIVE" ? "Activa" : "Suspendida"}</span></article>)}</div> : <div className="grid min-h-48 place-items-center px-5 py-8 text-center"><div><Building2 className="mx-auto size-8 text-ink-muted" /><p className="mt-3 font-bold text-ink">No encontramos organizaciones con estos filtros.</p><button className="mt-4 inline-flex min-h-10 items-center gap-2 rounded-lg px-3 text-sm font-semibold text-accent hover:bg-accent-soft" onClick={clear} type="button"><X className="size-4" />Limpiar filtros</button></div></div>}{filtered.length ? <div className="space-y-3 border-t border-line px-4 py-4 sm:px-5"><p className="text-xs text-ink-muted">Mostrando {range.start}–{range.end} de {filtered.length} organizaciones</p><Pagination onPageChange={setPage} page={page} pageSize={SUPERADMIN_PAGE_SIZE} totalItems={filtered.length} /></div> : null}</div>;
}
