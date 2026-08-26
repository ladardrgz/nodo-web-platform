import { AlertTriangle, Clock3, PackageSearch, ShieldCheck, Wrench } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { REPAIR_STATUS, type RepairOrder, type RepairStatus } from "@/features/repairs/types";

type Tone = "blue" | "violet" | "amber" | "orange" | "green";

const toneClasses: Record<Tone, string> = {
  blue: "border-accent/25 bg-accent-soft text-accent",
  violet: "border-[color:var(--status-violet)]/25 bg-[var(--status-violet-soft)] text-[var(--status-violet)]",
  amber: "border-[color:var(--status-amber)]/25 bg-[var(--status-amber-soft)] text-[var(--status-amber)]",
  orange: "border-[color:var(--status-orange)]/25 bg-[var(--status-orange-soft)] text-[var(--status-orange)]",
  green: "border-[color:var(--status-green)]/25 bg-[var(--status-green-soft)] text-[var(--status-green)]",
};

interface Metric {
  icon: LucideIcon;
  label: string;
  tone: Tone;
  value: number;
}

export function OperationalSummary({ repairs }: { repairs: RepairOrder[] }) {
  const inactive: RepairStatus[] = [REPAIR_STATUS.DELIVERED, REPAIR_STATUS.CANCELLED, REPAIR_STATUS.UNREPAIRABLE];
  const count = (status: RepairStatus) => repairs.filter((repair) => repair.status === status).length;
  const metrics: Metric[] = [
    { icon: Wrench, label: "Reparaciones activas", tone: "blue", value: repairs.filter((repair) => !inactive.includes(repair.status)).length },
    { icon: ShieldCheck, label: "Esperando aprobación", tone: "violet", value: count(REPAIR_STATUS.WAITING_APPROVAL) },
    { icon: PackageSearch, label: "Esperando repuesto", tone: "amber", value: count(REPAIR_STATUS.WAITING_PART) },
    { icon: AlertTriangle, label: "Demoradas", tone: "orange", value: count(REPAIR_STATUS.DELAYED) },
    { icon: Clock3, label: "Listas para retirar", tone: "green", value: count(REPAIR_STATUS.READY_FOR_PICKUP) },
  ];

  return (
    <section aria-labelledby="operational-summary-title">
      <div className="mb-3 flex items-end justify-between gap-3">
        <div><p className="text-xs font-bold uppercase tracking-[0.14em] text-accent">Prioridades</p><h2 className="mt-1 text-lg font-bold text-app-text" id="operational-summary-title">Resumen operativo</h2></div>
      </div>
      <div className="grid grid-cols-2 gap-3 xl:grid-cols-5">
        {metrics.map(({ icon: Icon, label, tone, value }) => (
          <article className="rounded-xl border border-app-border bg-app-card p-3.5 last:col-span-2 xl:last:col-span-1" key={label}>
            <div className="flex items-center justify-between gap-3">
              <span className={`grid size-9 shrink-0 place-items-center rounded-lg border ${toneClasses[tone]}`}><Icon aria-hidden="true" className="size-4.5" /></span>
              <strong className="text-xl font-bold tabular-nums text-app-text">{value}</strong>
            </div>
            <p className="mt-3 text-sm font-semibold leading-5 text-app-text-secondary">{label}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
