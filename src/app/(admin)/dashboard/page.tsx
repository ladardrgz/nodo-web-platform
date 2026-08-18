import { AlertTriangle, Clock3, PackageSearch, ShieldCheck, Wrench } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";

import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DemoDataNotice } from "@/components/ui/DemoDataNotice";
import { PageHeader } from "@/components/ui/PageHeader";
import { StatCard } from "@/components/ui/StatCard";
import { StatusBadge } from "@/components/ui/StatusBadge";
import {
  REPAIR_STATUS,
  type RepairStatus,
} from "@/features/repairs/types";
import { formatDateTime } from "@/lib/format";
import { mockRepairs, recentActivity } from "@/data/mock-repairs";
import { isDemoDataEnabled } from "@/lib/demo";

export const metadata: Metadata = { title: "Dashboard" };

export default function DashboardPage() {
  const demoEnabled = isDemoDataEnabled();
  const repairs = demoEnabled ? mockRepairs : [];
  const activity = demoEnabled ? recentActivity : [];
  const inactiveStatuses: RepairStatus[] = [
    REPAIR_STATUS.DELIVERED,
    REPAIR_STATUS.CANCELLED,
    REPAIR_STATUS.UNREPAIRABLE,
  ];
  const active = repairs.filter(
    (repair) => !inactiveStatuses.includes(repair.status),
  ).length;
  const count = (status: (typeof REPAIR_STATUS)[keyof typeof REPAIR_STATUS]) => repairs.filter((repair) => repair.status === status).length;

  return (
    <div className="space-y-6 sm:space-y-8">
      <PageHeader eyebrow="Resumen operativo" title="Dashboard" description="Lo importante del taller, ordenado por acciones que requieren atención." actions={<ButtonLink href="/repairs/new">Nueva reparación</ButtonLink>} />
      {demoEnabled ? <DemoDataNotice /> : null}

      <section aria-label="Métricas operativas" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard description="Órdenes todavía no finalizadas." icon={<Wrench className="size-5" />} label="Reparaciones activas" value={active} />
        <StatCard description="Requieren una decisión del cliente." icon={<ShieldCheck className="size-5" />} label="Esperando aprobación" tone="violet" value={count(REPAIR_STATUS.WAITING_APPROVAL)} />
        <StatCard description="Detenidas hasta recibir una pieza." icon={<PackageSearch className="size-5" />} label="Esperando repuesto" tone="amber" value={count(REPAIR_STATUS.WAITING_PART)} />
        <StatCard description="Necesitan una actualización clara." icon={<AlertTriangle className="size-5" />} label="Demoradas" tone="orange" value={count(REPAIR_STATUS.DELAYED)} />
        <StatCard description="Disponibles para coordinar entrega." icon={<Clock3 className="size-5" />} label="Listas para retirar" tone="green" value={count(REPAIR_STATUS.READY_FOR_PICKUP)} />
      </section>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.45fr)_minmax(330px,0.75fr)]">
        <Card className="overflow-hidden">
          <div className="flex items-center justify-between border-b border-border px-5 py-4">
            <div><h2 className="font-bold text-primary">Reparaciones recientes</h2><p className="mt-1 text-xs text-muted">Últimas órdenes con actividad.</p></div>
            <Link className="text-sm font-bold text-accent hover:text-accent-strong" href="/repairs">Ver todas</Link>
          </div>
          <div className="divide-y divide-border">
            {repairs.slice(0, 5).map((repair) => (
              <Link className="grid gap-3 px-5 py-4 hover:bg-slate-50 sm:grid-cols-[1fr_auto] sm:items-center" href={`/repairs/${repair.id}`} key={repair.id}>
                <div className="min-w-0"><p className="text-xs font-bold uppercase tracking-wide text-accent">{repair.orderNumber}</p><strong className="mt-1 block truncate text-sm text-primary">{repair.device.brand} {repair.device.model} · {repair.customerName}</strong><p className="mt-1 truncate text-xs text-muted">{repair.reportedProblem}</p></div>
                <StatusBadge compact status={repair.status} />
              </Link>
            ))}
          </div>
        </Card>

        <Card className="overflow-hidden">
          <div className="border-b border-border px-5 py-4"><h2 className="font-bold text-primary">Actividad reciente</h2><p className="mt-1 text-xs text-muted">Eventos relevantes de las órdenes.</p></div>
          <div className="divide-y divide-border">
            {activity.slice(0, 5).map((event) => (
              <Link className="block px-5 py-4 hover:bg-slate-50" href={`/repairs/${event.repairId}`} key={event.id}>
                <div className="flex items-start gap-3"><span className="mt-1 size-2 shrink-0 rounded-full bg-accent" /><div><strong className="text-sm text-primary">{event.title}</strong><p className="mt-1 text-xs leading-5 text-muted">{event.device} · {event.orderNumber}</p><time className="mt-1 block text-[11px] font-semibold text-slate-400">{formatDateTime(event.createdAt)}</time></div></div>
              </Link>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}
