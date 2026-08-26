import { ArrowLeft, CalendarDays, ClipboardCheck, Package, UserRound } from "lucide-react";
/* Signed, short-lived Storage URLs are rendered without Next image optimization. */
/* eslint-disable @next/next/no-img-element */
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { RepairTimeline } from "@/features/repairs/components/RepairTimeline";
import { getOrganizationRepair } from "@/features/repairs/repository";
import { INSPECTION_STATUSES } from "@/features/repairs/reception/inspection";
import { formatDate, formatDateTime } from "@/lib/format";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

interface RepairDetailPageProps { params: Promise<{ id: string }> }

export const metadata: Metadata = { title: "Reparación" };

export default async function RepairDetailPage({ params }: RepairDetailPageProps) {
  const { organization } = await requireOwnerOrganization();
  const { id } = await params;
  const repair = await getOrganizationRepair(organization.id, id);
  if (!repair) notFound();

  return (
    <div className="space-y-6">
      <Link className="inline-flex items-center gap-2 text-sm font-bold text-muted hover:text-accent" href="/repairs"><ArrowLeft className="size-4" />Volver a reparaciones</Link>
      <PageHeader eyebrow={repair.orderNumber} title={`${repair.device.brand} ${repair.device.model}`} description={repair.reportedProblem} actions={<><StatusBadge status={repair.status} /><ButtonLink href={`/customers/${repair.customerId}`} variant="secondary">Ver cliente</ButtonLink></>} />
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,0.65fr)]">
        <div className="space-y-5">
          <Card className="p-5 sm:p-6"><div className="flex items-center justify-between gap-3"><div><h2 className="font-bold text-primary">Recepción original</h2><p className="mt-1 text-xs text-muted">Snapshot inmutable del estado de ingreso.</p></div><span className="rounded-full bg-success-soft px-2.5 py-1 text-xs font-bold text-success ring-1 ring-inset ring-success/25">Confirmada</span></div><dl className="mt-6 grid gap-5 sm:grid-cols-2"><Detail icon={<UserRound />} label="Cliente" value={repair.customerName} /><Detail icon={<Package />} label="Dispositivo" value={`${repair.deviceTypeName ?? "Dispositivo"} · ${repair.device.brand} ${repair.device.model}`} /><Detail icon={<CalendarDays />} label="Fecha de ingreso" value={formatDateTime(repair.receivedAt)} /><Detail icon={<ClipboardCheck />} label="Estado físico calculado" value={`${repair.calculatedCondition} · ${repair.conditionScore} puntos`} /></dl><div className="mt-6 grid gap-4 border-t border-border pt-5"><section><h3 className="text-xs font-bold uppercase tracking-wide text-muted">Problema informado</h3><p className="mt-2 text-sm leading-6 text-primary">{repair.reportedProblem}</p></section><section><h3 className="text-xs font-bold uppercase tracking-wide text-muted">Observaciones de recepción</h3><p className="mt-2 text-sm leading-6 text-primary">{repair.intakeNotes}</p></section><section><h3 className="text-xs font-bold uppercase tracking-wide text-muted">Accesorios</h3><p className="mt-2 text-sm leading-6 text-primary">{repair.accessories.length ? repair.accessories.join(", ") : "No se registraron accesorios."}</p></section></div></Card>
          <Card className="p-5 sm:p-6"><h2 className="font-bold text-primary">Inspección física</h2><p className="mt-1 text-xs text-muted">Estados observados al confirmar la recepción.</p><div className="mt-5 divide-y divide-border rounded-xl border border-border">{repair.inspection.map((item) => <div className="grid gap-2 px-4 py-3 sm:grid-cols-[minmax(140px,.8fr)_minmax(150px,.6fr)_minmax(0,1fr)]" key={item.id}><strong className="text-sm text-primary">{item.label}{item.critical ? <span className="ml-2 text-xs text-danger">Importante</span> : null}</strong><span className="text-sm text-muted">{INSPECTION_STATUSES[item.condition as keyof typeof INSPECTION_STATUSES]?.label ?? item.condition}</span><span className="text-sm text-muted">{item.observation || "Sin observaciones."}</span></div>)}</div></Card>
          {repair.photos.length ? <Card className="p-5 sm:p-6"><h2 className="font-bold text-primary">Evidencia fotográfica</h2><div className="mt-5 grid gap-4 sm:grid-cols-2">{repair.photos.map((photo) => <figure className="overflow-hidden rounded-xl border border-border bg-surface-soft" key={photo.id}><img alt={photo.description || "Evidencia fotográfica de la recepción"} className="aspect-video w-full object-contain" src={photo.url} /><figcaption className="p-3 text-xs text-muted">{photo.description || "Sin descripción."}</figcaption></figure>)}</div></Card> : null}
          <Card className="p-5 sm:p-6"><h2 className="font-bold text-primary">Timeline de la reparación</h2><p className="mt-1 text-xs text-muted">Eventos visibles del seguimiento.</p><div className="mt-6"><RepairTimeline events={repair.timeline} /></div></Card>
        </div>
        <aside className="space-y-5">
          <Card className="p-5"><h2 className="font-bold text-primary">Estado actual</h2><div className="mt-4"><StatusBadge status={repair.status} /></div><dl className="mt-5 space-y-4 border-t border-border pt-5"><Summary label="Número de orden" value={repair.orderNumber} /><Summary label="Ingreso" value={formatDate(repair.receivedAt)} /><Summary label="Recepción" value={repair.intakeStatus === "CONFIRMED" ? "Confirmada" : "Borrador"} />{repair.estimatedDate ? <Summary label="Fecha estimada" value={formatDate(repair.estimatedDate)} /> : null}</dl></Card>
          <Card className="p-5"><h2 className="font-bold text-primary">Trazabilidad</h2><p className="mt-3 text-sm leading-6 text-muted">La recepción original permanece inmutable. Los diagnósticos y hallazgos posteriores se registrarán como eventos separados.</p></Card>
        </aside>
      </div>
    </div>
  );
}

function Detail({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return <div className="flex items-start gap-3"><span className="mt-0.5 text-accent [&>svg]:size-4">{icon}</span><div><dt className="text-xs font-bold uppercase tracking-wide text-muted">{label}</dt><dd className="mt-1 text-sm font-semibold text-primary">{value}</dd></div></div>;
}

function Summary({ label, value }: { label: string; value: string }) {
  return <div><dt className="text-xs font-bold uppercase tracking-wide text-muted">{label}</dt><dd className="mt-1 text-sm font-semibold text-primary">{value}</dd></div>;
}
