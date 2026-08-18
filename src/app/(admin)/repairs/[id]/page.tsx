import { ArrowLeft, CalendarDays, ClipboardCheck, Package, UserRound } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { mockRepairs } from "@/data/mock-repairs";
import { deviceTypeLabels } from "@/features/customers/types";
import { RepairTimeline } from "@/features/repairs/components/RepairTimeline";
import { formatDate, formatDateTime } from "@/lib/format";
import { isDemoDataEnabled } from "@/lib/demo";

interface RepairDetailPageProps { params: Promise<{ id: string }> }

export async function generateMetadata({ params }: RepairDetailPageProps): Promise<Metadata> {
  if (!isDemoDataEnabled()) return { title: "Reparación" };
  const { id } = await params;
  const repair = mockRepairs.find((item) => item.id === id);
  return { title: repair?.orderNumber ?? "Reparación" };
}

export default async function RepairDetailPage({ params }: RepairDetailPageProps) {
  if (!isDemoDataEnabled()) notFound();
  const { id } = await params;
  const repair = mockRepairs.find((item) => item.id === id);
  if (!repair) notFound();

  return (
    <div className="space-y-6">
      <Link className="inline-flex items-center gap-2 text-sm font-bold text-muted hover:text-accent" href="/repairs"><ArrowLeft className="size-4" />Volver a reparaciones</Link>
      <PageHeader eyebrow={repair.orderNumber} title={`${repair.device.brand} ${repair.device.model}`} description={repair.reportedProblem} actions={<><StatusBadge status={repair.status} /><ButtonLink href={`/customers/${repair.customerId}`} variant="secondary">Ver cliente</ButtonLink></>} />
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,0.65fr)]">
        <div className="space-y-5">
          <Card className="p-5 sm:p-6"><div className="flex items-center justify-between gap-3"><div><h2 className="font-bold text-primary">Recepción original</h2><p className="mt-1 text-xs text-muted">Información inicial del ingreso.</p></div><span className={`rounded-full px-2.5 py-1 text-xs font-bold ring-1 ring-inset ${repair.intakeStatus === "CONFIRMED" ? "bg-emerald-50 text-emerald-800 ring-emerald-200" : "bg-amber-50 text-amber-800 ring-amber-200"}`}>{repair.intakeStatus === "CONFIRMED" ? "Confirmada" : "Borrador"}</span></div><dl className="mt-6 grid gap-5 sm:grid-cols-2"><Detail icon={<UserRound />} label="Cliente" value={repair.customerName} /><Detail icon={<Package />} label="Dispositivo" value={`${deviceTypeLabels[repair.device.type]} · ${repair.device.brand} ${repair.device.model}`} /><Detail icon={<CalendarDays />} label="Fecha de ingreso" value={formatDateTime(repair.receivedAt)} /><Detail icon={<ClipboardCheck />} label="Última actualización" value={formatDateTime(repair.updatedAt)} /></dl><div className="mt-6 grid gap-4 border-t border-border pt-5"><section><h3 className="text-xs font-bold uppercase tracking-wide text-muted">Problema informado</h3><p className="mt-2 text-sm leading-6 text-primary">{repair.reportedProblem}</p></section><section><h3 className="text-xs font-bold uppercase tracking-wide text-muted">Estado físico y observaciones</h3><p className="mt-2 text-sm leading-6 text-primary">{repair.intakeNotes}</p></section><section><h3 className="text-xs font-bold uppercase tracking-wide text-muted">Accesorios</h3><p className="mt-2 text-sm leading-6 text-primary">{repair.accessories.length ? repair.accessories.join(", ") : "No se registraron accesorios."}</p></section></div></Card>
          <Card className="p-5 sm:p-6"><h2 className="font-bold text-primary">Timeline de la reparación</h2><p className="mt-1 text-xs text-muted">Eventos visibles del seguimiento.</p><div className="mt-6"><RepairTimeline events={repair.timeline} /></div></Card>
        </div>
        <aside className="space-y-5">
          <Card className="p-5"><h2 className="font-bold text-primary">Estado actual</h2><div className="mt-4"><StatusBadge status={repair.status} /></div><dl className="mt-5 space-y-4 border-t border-border pt-5"><Summary label="Número de orden" value={repair.orderNumber} /><Summary label="Ingreso" value={formatDate(repair.receivedAt)} /><Summary label="Recepción" value={repair.intakeStatus === "CONFIRMED" ? "Confirmada" : "Borrador"} />{repair.estimatedDate ? <Summary label="Fecha estimada" value={formatDate(repair.estimatedDate)} /> : null}</dl></Card>
          <Card className="p-5"><h2 className="font-bold text-primary">Próximos módulos</h2><ul className="mt-4 space-y-3 text-sm text-muted"><li className="rounded-lg bg-surface-soft p-3">Diagnóstico técnico</li><li className="rounded-lg bg-surface-soft p-3">Presupuesto versionado</li><li className="rounded-lg bg-surface-soft p-3">Fotografías privadas</li><li className="rounded-lg bg-surface-soft p-3">Anexos inmutables</li></ul></Card>
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
