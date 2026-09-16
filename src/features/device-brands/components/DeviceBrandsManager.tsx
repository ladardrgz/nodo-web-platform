"use client";

import {
  ArrowLeft, ArrowRight, Database, Gamepad2, Laptop, Monitor, MoreVertical,
  Pencil, Plus, Search, Smartphone, Tablet, Tag,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState, type ComponentType } from "react";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { IconInput } from "@/components/ui/IconInput";
import { CatalogModal } from "@/features/repairs/reception/CatalogModal";
import { createDeviceBrandFromAdminAction, createDeviceModelFromAdminAction, deletePrivateDeviceBrandAction, getDeviceBrandPageAction, type DeviceBrandAdminRow } from "@/features/device-brands/actions";

type DeviceType = { id: string; name: string };
type DeviceTypeIcon = ComponentType<{ className?: string; "aria-hidden"?: boolean }>;

function getDeviceTypeIcon(name: string): DeviceTypeIcon {
  const normalized = name.toLocaleLowerCase("es-AR");
  if (normalized.includes("notebook") || normalized.includes("laptop")) return Laptop;
  if (normalized.includes("escritorio") || normalized.includes("desktop") || normalized === "pc") return Monitor;
  if (normalized.includes("tablet")) return Tablet;
  if (normalized.includes("consol")) return Gamepad2;
  if (normalized.includes("celular") || normalized.includes("móvil") || normalized.includes("movil")) return Smartphone;
  return Tag;
}

function BrandMark({ name }: { name: string }) {
  return <span aria-hidden="true" className="grid size-9 shrink-0 place-items-center rounded-xl bg-accent-soft text-sm font-black text-accent">{name.slice(0, 1).toUpperCase()}</span>;
}

export function DeviceBrandsManager({ deviceTypes, initialDeviceTypeId }: { deviceTypes: DeviceType[]; initialDeviceTypeId?: string }) {
  const [deviceTypeId, setDeviceTypeId] = useState(initialDeviceTypeId && deviceTypes.some((type) => type.id === initialDeviceTypeId) ? initialDeviceTypeId : (deviceTypes[0]?.id ?? ""));
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const pageSize = 5;
  const [rows, setRows] = useState<DeviceBrandAdminRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [modal, setModal] = useState<{ kind: "brand" } | { kind: "model"; brand: DeviceBrandAdminRow } | null>(null);
  const [pendingDeletion, setPendingDeletion] = useState<DeviceBrandAdminRow | null>(null);
  const typeName = useMemo(() => deviceTypes.find((type) => type.id === deviceTypeId)?.name ?? "", [deviceTypeId, deviceTypes]);

  const refresh = useCallback(async () => {
    if (!deviceTypeId) return;
    setLoading(true);
    const result = await getDeviceBrandPageAction({ deviceTypeId, query, page, pageSize });
    setLoading(false);
    if (!result.ok || !result.data) { setMessage(result.message); setRows([]); setTotal(0); return; }
    setRows(result.data.rows); setTotal(result.data.total);
  }, [deviceTypeId, page, query]);
  useEffect(() => { const timer = window.setTimeout(() => { void refresh(); }, 120); return () => window.clearTimeout(timer); }, [refresh]);

  const chooseType = (id: string) => { setDeviceTypeId(id); setPage(1); setQuery(""); };
  const save = async (name: string) => {
    if (!modal) return;
    const result = modal.kind === "brand" ? await createDeviceBrandFromAdminAction({ name, deviceTypeId }) : await createDeviceModelFromAdminAction({ name, deviceTypeId, brandId: modal.brand.id });
    setMessage(result.message); if (result.ok) { setModal(null); await refresh(); }
  };
  const remove = async () => {
    if (!pendingDeletion) return;
    const result = await deletePrivateDeviceBrandAction({ deviceTypeId, brandId: pendingDeletion.id });
    setMessage(result.message); setPendingDeletion(null); if (result.ok) await refresh();
  };

  return <section className="mx-auto max-w-[1240px] space-y-6 pb-4">
    <div className="flex items-center gap-2 text-sm text-muted"><span>Catálogos</span><span aria-hidden="true">›</span><span className="text-primary">Marcas</span></div>
    <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_390px] xl:items-center">
      <div className="flex items-start gap-4 sm:gap-5"><span className="grid size-16 shrink-0 place-items-center rounded-2xl border border-accent/25 bg-accent-soft text-accent shadow-sm"><Tag aria-hidden="true" className="size-8" /></span><div><h1 className="text-3xl font-bold tracking-tight text-primary sm:text-4xl">Marcas de dispositivos</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-muted sm:text-base">Administrá las marcas comerciales del equipo completo y sus modelos asociados.</p></div></div>
      <Card className="flex items-center gap-4 border-accent/20 bg-accent-soft/70 p-4 shadow-none"><span className="grid size-14 shrink-0 place-items-center rounded-full bg-accent/15 text-accent"><Database aria-hidden="true" className="size-7" /></span><div><h2 className="font-bold text-primary">Catálogo central</h2><p className="mt-1 text-sm leading-5 text-muted">Las marcas se utilizan en los catálogos de modelos y en la recepción de dispositivos.</p></div></Card>
    </div>
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">{deviceTypes.map((type) => { const Icon = getDeviceTypeIcon(type.name); const selected = type.id === deviceTypeId; return <button aria-pressed={selected} className={`flex min-h-14 items-center justify-center gap-2 rounded-xl border px-3 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent ${selected ? "border-accent-button bg-accent-button text-white shadow-[0_7px_18px_rgb(var(--shadow-color)/16%)]" : "border-line bg-surface text-primary hover:border-accent/45 hover:bg-surface-hover"}`} key={type.id} onClick={() => chooseType(type.id)} type="button"><Icon aria-hidden={true} className="size-5" />{type.name}</button>; })}</div>
    <div className="flex flex-col gap-3 lg:flex-row lg:items-end"><label className="block min-w-0 flex-1"><span className="sr-only">Buscar marcas</span><IconInput className="!min-h-12 !rounded-xl" clearLabel="Limpiar búsqueda de marcas" leadingIcon={<Search className="size-5" />} onChange={(event) => { setQuery(event.target.value); setPage(1); }} onClear={() => setQuery("")} placeholder="Buscar por nombre de marca…" type="search" value={query} /></label><Button className="h-12 rounded-xl px-5" disabled={!deviceTypeId} onClick={() => setModal({ kind: "brand" })}><Plus aria-hidden="true" className="size-5" />Nueva marca</Button></div>
    <Card className="overflow-hidden border-line/90"><div className="overflow-x-auto"><table className="w-full min-w-[770px] text-left"><thead><tr className="border-b border-line bg-surface-soft/70 text-xs font-bold uppercase tracking-wide text-muted"><th className="px-6 py-4">Marca</th><th className="px-5 py-4">Tipo</th><th className="px-5 py-4">Modelos</th><th className="px-5 py-4">Estado</th><th className="px-5 py-4 text-right">Acciones</th></tr></thead><tbody>{loading ? <tr><td className="px-6 py-10 text-sm text-muted" colSpan={5}>Cargando marcas…</td></tr> : rows.map((brand) => <tr className="border-b border-line/80 transition-colors last:border-0 hover:bg-surface-hover/70" key={brand.id}><td className="px-6 py-4"><div className="flex items-center gap-3"><BrandMark name={brand.name} /><strong className="text-sm text-primary">{brand.name}</strong></div></td><td className="px-5 py-4 text-sm text-muted">{typeName}</td><td className="px-5 py-4"><strong className="block text-sm text-primary">{brand.modelCount} {brand.modelCount === 1 ? "modelo" : "modelos"}</strong><span className="mt-0.5 block max-w-[230px] truncate text-xs text-muted">{brand.models.length ? brand.models.join(", ") : "Sin modelos cargados"}</span></td><td className="px-5 py-4"><span className={brand.isActive ? "inline-flex items-center gap-1.5 rounded-full bg-success-soft px-2.5 py-1 text-xs font-bold text-success" : "inline-flex rounded-full bg-surface-soft px-2.5 py-1 text-xs font-bold text-muted"}>{brand.isActive ? <span className="size-1.5 rounded-full bg-current" /> : null}{brand.isActive ? "Activa" : "Inactiva"}</span></td><td className="px-5 py-4"><div className="flex justify-end gap-2"><Button aria-label={`Agregar modelo a ${brand.name}`} className="rounded-lg" onClick={() => setModal({ kind: "model", brand })} size="sm" variant="secondary"><Plus aria-hidden="true" className="size-4" />Agregar modelo</Button>{brand.isPrivate ? <><Button aria-label={`Editar ${brand.name}`} className="!px-2.5" size="sm" variant="secondary"><Pencil aria-hidden="true" className="size-4" /></Button><Button aria-label={`Dar de baja ${brand.name}`} className="!px-2.5" onClick={() => setPendingDeletion(brand)} size="sm" variant="secondary"><MoreVertical aria-hidden="true" className="size-4" /></Button></> : null}</div></td></tr>)}</tbody></table></div>{!loading && !rows.length ? <div className="border-t border-line"><EmptyState description={query ? "Revisá cómo está escrito o probá con menos caracteres." : "Registrá la primera marca comercial disponible para este tipo de dispositivo."} title={query ? "No encontramos marcas con ese nombre." : "No hay marcas para este tipo."} /></div> : null}{rows.length ? <div className="flex items-center justify-between border-t border-line px-5 py-4 text-sm text-muted"><span>Mostrando {rows.length} de {total} marcas</span><div className="flex gap-2"><button aria-label="Página anterior" className="grid size-9 place-items-center rounded-lg border border-line bg-surface hover:bg-surface-hover disabled:opacity-40" disabled={page === 1} onClick={() => setPage((current) => Math.max(1, current - 1))} type="button"><ArrowLeft aria-hidden="true" className="size-4" /></button><span className="grid size-9 place-items-center rounded-lg bg-accent-button text-sm font-bold text-white">{page}</span><button aria-label="Página siguiente" className="grid size-9 place-items-center rounded-lg border border-line bg-surface hover:bg-surface-hover disabled:opacity-40" disabled={page * pageSize >= total} onClick={() => setPage((current) => current + 1)} type="button"><ArrowRight aria-hidden="true" className="size-4" /></button></div></div> : null}</Card>
    <div className="grid gap-4 md:grid-cols-2"><Card className="flex items-center gap-4 p-5"><span className="grid size-14 place-items-center rounded-full bg-accent-soft text-accent"><Tag aria-hidden="true" className="size-7" /></span><div><p className="text-sm text-muted">Total de marcas</p><strong className="text-3xl text-primary">{total}</strong><p className="text-xs text-muted">En este tipo de dispositivo</p></div></Card><Card className="flex items-center gap-4 p-5"><span className="grid size-14 place-items-center rounded-full bg-success-soft text-success"><Database aria-hidden="true" className="size-7" /></span><div><p className="text-sm text-muted">Total de modelos</p><strong className="text-3xl text-primary">{rows.reduce((sum, brand) => sum + brand.modelCount, 0)}</strong><p className="text-xs text-muted">Asociados a estas marcas</p></div></Card></div>
    {message ? <p aria-live="polite" className="text-sm text-muted">{message}</p> : null}
    <CatalogModal busy={false} error={undefined} label={modal?.kind === "model" ? "Nombre del modelo" : "Nombre de la marca"} onClose={() => setModal(null)} onSubmit={save} open={modal !== null} title={modal?.kind === "model" ? `Agregar modelo a ${modal.brand.name}` : "Nueva marca"} />
    {pendingDeletion ? <div className="fixed inset-0 z-[90] flex items-start justify-center overflow-y-auto bg-brand-surface/40 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setPendingDeletion(null); }}><div aria-modal="true" aria-labelledby="delete-device-brand-title" className="w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><h2 className="font-bold text-primary" id="delete-device-brand-title">Eliminar marca</h2><p className="mt-2 text-sm leading-6 text-muted">Vas a eliminar <strong>{pendingDeletion.name}</strong> del catálogo de {typeName}. Sólo se permitirá si no forma parte del historial operativo.</p><div className="mt-5 flex justify-end gap-2"><Button onClick={() => setPendingDeletion(null)} variant="secondary">Cancelar</Button><Button onClick={() => void remove()} variant="danger">Eliminar marca</Button></div></div></div> : null}
  </section>;
}
