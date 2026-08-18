"use client";

import { Search, X } from "lucide-react";
import { useMemo, useState } from "react";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { Pagination } from "@/components/ui/Pagination";
import { inventoryCategoryLabels, type InventoryCategory, type InventoryItem } from "@/features/inventory/types";
import { formatCurrency } from "@/lib/format";

const PAGE_SIZE = 10;

function stockState(item: InventoryItem) {
  if (item.currentStock === 0) return { label: "Sin stock", className: "bg-red-50 text-red-800 ring-red-200" };
  if (item.currentStock <= item.minimumStock) return { label: "Stock bajo", className: "bg-amber-50 text-amber-800 ring-amber-200" };
  return { label: "Disponible", className: "bg-emerald-50 text-emerald-800 ring-emerald-200" };
}

export function InventoryExplorer({ items }: { items: InventoryItem[] }) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<InventoryCategory | "ALL">("ALL");
  const [onlyAlerts, setOnlyAlerts] = useState(false);
  const [page, setPage] = useState(1);
  const filtered = useMemo(() => items.filter((item) => {
    const normalized = query.trim().toLocaleLowerCase("es");
    const matches = !normalized || [item.name, item.code, item.brand ?? "", item.compatibility ?? ""].some((value) => value.toLocaleLowerCase("es").includes(normalized));
    return matches && (category === "ALL" || item.category === category) && (!onlyAlerts || item.currentStock <= item.minimumStock);
  }), [category, items, onlyAlerts, query]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const visibleItems = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const clearFilters = () => { setQuery(""); setCategory("ALL"); setOnlyAlerts(false); setPage(1); };

  return <div className="space-y-5"><Card className="p-4"><div className="grid gap-3 lg:grid-cols-[minmax(260px,1fr)_210px_auto_auto]"><label className="relative block"><span className="sr-only">Buscar inventario</span><Search className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-slate-400" /><input className="field-control pl-11" onChange={(event) => { setQuery(event.target.value); setPage(1); }} placeholder="Producto, código, marca o compatibilidad" type="search" value={query} /></label><select aria-label="Filtrar por categoría" className="field-control" onChange={(event) => { setCategory(event.target.value as InventoryCategory | "ALL"); setPage(1); }} value={category}><option value="ALL">Todas las categorías</option>{Object.entries(inventoryCategoryLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><label className="flex min-h-11 items-center gap-3 rounded-lg border border-border bg-white px-4 text-sm font-semibold text-primary"><input checked={onlyAlerts} className="size-4 accent-blue-600" onChange={(event) => { setOnlyAlerts(event.target.checked); setPage(1); }} type="checkbox" />Sólo alertas</label><Button disabled={!query && category === "ALL" && !onlyAlerts} onClick={clearFilters} variant="secondary"><X className="size-4" />Limpiar</Button></div><p aria-live="polite" className="mt-3 text-xs font-semibold text-muted">{filtered.length} artículos encontrados</p></Card>{visibleItems.length ? <><Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full min-w-[760px] text-left"><thead><tr className="border-b border-border bg-surface-soft text-xs font-bold uppercase tracking-wide text-muted"><th className="px-5 py-3">Producto</th><th className="px-5 py-3">Categoría</th><th className="px-5 py-3">Stock</th><th className="px-5 py-3">Mínimo</th><th className="px-5 py-3">Precio</th><th className="px-5 py-3">Estado</th></tr></thead><tbody>{visibleItems.map((item) => { const state = stockState(item); return <tr className="border-b border-border last:border-0" key={item.id}><td className="px-5 py-4"><strong className="block text-sm text-primary">{item.name}</strong><span className="text-xs text-muted">{item.code}{item.compatibility ? ` · ${item.compatibility}` : ""}</span></td><td className="px-5 py-4 text-sm text-muted">{inventoryCategoryLabels[item.category]}</td><td className="px-5 py-4 text-lg font-bold text-primary">{item.currentStock}</td><td className="px-5 py-4 text-sm text-muted">{item.minimumStock}</td><td className="px-5 py-4 text-sm font-bold text-primary">{formatCurrency(item.price)}</td><td className="px-5 py-4"><span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-bold ring-1 ring-inset ${state.className}`}>{state.label}</span></td></tr>; })}</tbody></table></div></Card><Pagination onPageChange={setPage} page={safePage} pageSize={PAGE_SIZE} totalItems={filtered.length} /></> : <Card><EmptyState title="No hay artículos para mostrar" description="Modificá la búsqueda o desactivá alguno de los filtros." /></Card>}</div>;
}
