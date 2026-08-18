"use client";

import { Search, X } from "lucide-react";
import { useMemo, useState } from "react";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { Pagination } from "@/components/ui/Pagination";
import { repairStatusOptions } from "@/config/repair-status";
import { RepairCard } from "@/features/repairs/components/RepairCard";
import { RepairTable } from "@/features/repairs/components/RepairTable";
import type { RepairOrder, RepairStatus } from "@/features/repairs/types";

const PAGE_SIZE = 10;
const DEMO_REFERENCE_NOW = Date.parse("2026-08-17T00:00:00-03:00");

export function RepairsExplorer({ repairs }: { repairs: RepairOrder[] }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<RepairStatus | "ALL">("ALL");
  const [received, setReceived] = useState<"ALL" | "7_DAYS" | "30_DAYS" | "OLDER">("ALL");
  const [page, setPage] = useState(1);

  const filteredRepairs = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("es");
    return repairs.filter((repair) => {
      const matchesQuery = !normalized || [repair.orderNumber, repair.customerName, repair.device.brand, repair.device.model, repair.reportedProblem].some((value) => value.toLocaleLowerCase("es").includes(normalized));
      const matchesStatus = status === "ALL" || repair.status === status;
      const ageInDays = (DEMO_REFERENCE_NOW - Date.parse(repair.receivedAt)) / 86_400_000;
      const matchesDate = received === "ALL" || (received === "7_DAYS" ? ageInDays <= 7 : received === "30_DAYS" ? ageInDays <= 30 : ageInDays > 30);
      return matchesQuery && matchesStatus && matchesDate;
    });
  }, [query, received, repairs, status]);

  const totalPages = Math.max(1, Math.ceil(filteredRepairs.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const visibleRepairs = filteredRepairs.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const clearFilters = () => { setQuery(""); setStatus("ALL"); setReceived("ALL"); setPage(1); };

  return <div className="space-y-5"><Card className="p-4"><div className="grid gap-3 lg:grid-cols-[minmax(260px,1fr)_230px_190px_auto]"><label className="relative block"><span className="sr-only">Buscar reparaciones</span><Search className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-slate-400" /><input className="field-control pl-11" onChange={(event) => { setQuery(event.target.value); setPage(1); }} placeholder="Orden, cliente, equipo o problema" type="search" value={query} /></label><label><span className="sr-only">Filtrar por estado</span><select className="field-control" onChange={(event) => { setStatus(event.target.value as RepairStatus | "ALL"); setPage(1); }} value={status}><option value="ALL">Todos los estados</option>{repairStatusOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label><label><span className="sr-only">Filtrar por recepción</span><select className="field-control" onChange={(event) => { setReceived(event.target.value as typeof received); setPage(1); }} value={received}><option value="ALL">Cualquier fecha</option><option value="7_DAYS">Últimos 7 días</option><option value="30_DAYS">Últimos 30 días</option><option value="OLDER">Más de 30 días</option></select></label><Button disabled={!query && status === "ALL" && received === "ALL"} onClick={clearFilters} variant="secondary"><X className="size-4" />Limpiar</Button></div><p aria-live="polite" className="mt-3 text-xs font-semibold text-muted">{filteredRepairs.length} {filteredRepairs.length === 1 ? "reparación encontrada" : "reparaciones encontradas"}</p></Card>{visibleRepairs.length ? <><Card className="hidden overflow-hidden md:block"><RepairTable repairs={visibleRepairs} /></Card><div className="grid gap-4 md:hidden">{visibleRepairs.map((repair) => <RepairCard key={repair.id} repair={repair} />)}</div><Pagination onPageChange={setPage} page={safePage} pageSize={PAGE_SIZE} totalItems={filteredRepairs.length} /></> : <Card><EmptyState title="No encontramos reparaciones" description="Probá con otra búsqueda o quitá alguno de los filtros activos." /></Card>}</div>;
}
