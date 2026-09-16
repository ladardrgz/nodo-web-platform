"use client";

import { Search } from "lucide-react";
import { useMemo, useState } from "react";

import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import type { PriceItem } from "@/features/pricing/types";
import { formatCurrency, formatDate } from "@/lib/format";

export function PricingExplorer({ items }: { items: PriceItem[] }) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("ALL");
  const categories = useMemo(() => [...new Set(items.map((item) => item.category))].sort((left, right) => left.localeCompare(right, "es")), [items]);
  const filtered = useMemo(() => items.filter((item) => {
    const normalized = query.trim().toLocaleLowerCase("es");
    const matches = !normalized || [item.name, item.deviceType].some((value) => value.toLocaleLowerCase("es").includes(normalized));
    return matches && (category === "ALL" || item.category === category);
  }), [category, items, query]);

  return <div className="space-y-5"><Card className="p-4"><div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_260px]"><label className="relative block"><span className="sr-only">Buscar precios</span><Search className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-muted" /><input className="field-control pl-11" onChange={(event) => setQuery(event.target.value)} placeholder="Servicio, producto o dispositivo" type="search" value={query} /></label><select aria-label="Filtrar por categoría" className="field-control" disabled={!categories.length} onChange={(event) => setCategory(event.target.value)} value={category}><option value="ALL">Todas las categorías</option>{categories.map((name) => <option key={name} value={name}>{name}</option>)}</select></div></Card>{filtered.length ? <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">{filtered.map((item) => <Card className="p-5" key={item.id}><div className="flex items-start justify-between gap-3"><span className="rounded-full bg-accent-soft px-2.5 py-1 text-xs font-bold text-accent">{item.category}</span><span className="text-xs font-semibold text-muted">{item.deviceType}</span></div><h2 className="mt-4 font-bold text-primary">{item.name}</h2><p className="mt-3 text-2xl font-bold text-primary">{formatCurrency(item.price)}</p><div className="mt-4 border-t border-line pt-4 text-xs leading-5 text-muted"><p>Tiempo estimado: <strong className="text-primary">{item.estimatedTime}</strong></p><p>Actualizado: <strong className="text-primary">{formatDate(item.updatedAt)}</strong></p></div></Card>)}</div> : <Card><EmptyState title="No hay precios para mostrar" description={items.length ? "Probá otra búsqueda o seleccioná todas las categorías." : "El esquema actual todavía no cuenta con un catálogo tarifario."} /></Card>}</div>;
}
