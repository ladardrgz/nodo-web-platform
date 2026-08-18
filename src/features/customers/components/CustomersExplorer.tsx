"use client";

import { ArrowRight, Mail, Phone, Search, Smartphone, X } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { Pagination } from "@/components/ui/Pagination";
import type { Customer } from "@/features/customers/types";
import { getCustomerFullName } from "@/features/customers/types";
import type { RepairOrder } from "@/features/repairs/types";

const PAGE_SIZE = 8;
const DEMO_REFERENCE_NOW = Date.parse("2026-08-17T00:00:00-03:00");
const inactiveStatuses = new Set(["DELIVERED", "CANCELLED", "UNREPAIRABLE"]);

export function CustomersExplorer({ customers, repairs }: { customers: Customer[]; repairs: RepairOrder[] }) {
  const [query, setQuery] = useState("");
  const [activity, setActivity] = useState<"ALL" | "WITH_REPAIRS" | "WITHOUT_REPAIRS">("ALL");
  const [created, setCreated] = useState<"ALL" | "7_DAYS" | "30_DAYS" | "OLDER">("ALL");
  const [page, setPage] = useState(1);

  const activeRepairsByCustomer = useMemo(() => {
    const counts = new Map<string, number>();
    repairs.filter((repair) => !inactiveStatuses.has(repair.status)).forEach((repair) => counts.set(repair.customerId, (counts.get(repair.customerId) ?? 0) + 1));
    return counts;
  }, [repairs]);

  const filteredCustomers = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("es");
    return customers.filter((customer) => {
      const matchesQuery = !normalized || [getCustomerFullName(customer), customer.phone, customer.email].some((value) => value.toLocaleLowerCase("es").includes(normalized));
      const activeRepairs = activeRepairsByCustomer.get(customer.id) ?? 0;
      const matchesActivity = activity === "ALL" || (activity === "WITH_REPAIRS" ? activeRepairs > 0 : activeRepairs === 0);
      const ageInDays = (DEMO_REFERENCE_NOW - Date.parse(customer.createdAt)) / 86_400_000;
      const matchesCreated = created === "ALL" || (created === "7_DAYS" ? ageInDays <= 7 : created === "30_DAYS" ? ageInDays <= 30 : ageInDays > 30);
      return matchesQuery && matchesActivity && matchesCreated;
    });
  }, [activeRepairsByCustomer, activity, created, customers, query]);

  const totalPages = Math.max(1, Math.ceil(filteredCustomers.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const visibleCustomers = filteredCustomers.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const clearFilters = () => { setQuery(""); setActivity("ALL"); setCreated("ALL"); setPage(1); };

  return <div className="space-y-5"><Card className="p-4"><div className="grid gap-3 lg:grid-cols-[minmax(260px,1fr)_220px_190px_auto]"><label className="relative block"><span className="sr-only">Buscar clientes</span><Search className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-slate-400" /><input className="field-control pl-11" onChange={(event) => { setQuery(event.target.value); setPage(1); }} placeholder="Nombre, teléfono o correo" type="search" value={query} /></label><label><span className="sr-only">Filtrar por reparaciones</span><select className="field-control" onChange={(event) => { setActivity(event.target.value as typeof activity); setPage(1); }} value={activity}><option value="ALL">Cualquier actividad</option><option value="WITH_REPAIRS">Con reparaciones activas</option><option value="WITHOUT_REPAIRS">Sin reparaciones activas</option></select></label><label><span className="sr-only">Filtrar por alta</span><select className="field-control" onChange={(event) => { setCreated(event.target.value as typeof created); setPage(1); }} value={created}><option value="ALL">Cualquier fecha</option><option value="7_DAYS">Últimos 7 días</option><option value="30_DAYS">Últimos 30 días</option><option value="OLDER">Más de 30 días</option></select></label><Button disabled={!query && activity === "ALL" && created === "ALL"} onClick={clearFilters} variant="secondary"><X className="size-4" />Limpiar</Button></div><p aria-live="polite" className="mt-3 text-xs font-semibold text-muted">{filteredCustomers.length} {filteredCustomers.length === 1 ? "cliente" : "clientes"}</p></Card>{visibleCustomers.length ? <><div className="grid gap-4 lg:grid-cols-2">{visibleCustomers.map((customer) => { const activeRepairs = activeRepairsByCustomer.get(customer.id) ?? 0; return <Card className="p-5" key={customer.id}><div className="flex items-start justify-between gap-4"><div className="flex min-w-0 items-center gap-3"><span className="grid size-11 shrink-0 place-items-center rounded-full bg-blue-50 text-sm font-bold text-accent">{customer.firstName[0]}{customer.lastName[0]}</span><div className="min-w-0"><h2 className="truncate font-bold text-primary">{getCustomerFullName(customer)}</h2><p className="mt-1 text-xs text-muted">Cliente de demostración</p></div></div><Link aria-label={`Abrir perfil de ${getCustomerFullName(customer)}`} className="grid size-9 shrink-0 place-items-center rounded-lg text-muted hover:bg-blue-50 hover:text-accent" href={`/customers/${customer.id}`}><ArrowRight className="size-4" /></Link></div><div className="mt-5 grid gap-2 text-sm text-muted sm:grid-cols-2"><span className="flex items-center gap-2"><Phone className="size-4" />{customer.phone}</span><span className="flex min-w-0 items-center gap-2"><Mail className="size-4 shrink-0" /><span className="truncate">{customer.email}</span></span></div><div className="mt-5 grid grid-cols-2 gap-3 border-t border-border pt-4"><div><p className="text-xs font-semibold text-muted">Equipos</p><p className="mt-1 flex items-center gap-2 text-lg font-bold text-primary"><Smartphone className="size-4 text-accent" />{customer.devices.length}</p></div><div><p className="text-xs font-semibold text-muted">Reparaciones activas</p><p className="mt-1 text-lg font-bold text-primary">{activeRepairs}</p></div></div></Card>; })}</div><Pagination onPageChange={setPage} page={safePage} pageSize={PAGE_SIZE} totalItems={filteredCustomers.length} /></> : <Card><EmptyState showIllustration title="No encontramos clientes" description="Revisá la combinación de búsqueda y filtros aplicados." /></Card>}</div>;
}
