import {
  AlertTriangle,
  Clock3,
  PackageSearch,
  ShieldCheck,
  Wrench,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import {
  REPAIR_STATUS,
  type RepairOrder,
  type RepairStatus,
} from "@/features/repairs/types";

type Tone = "blue" | "violet" | "amber" | "orange" | "green";

const iconToneClasses: Record<Tone, string> = {
  blue: "border-accent/30 bg-accent-soft text-accent",
  violet:
    "border-[color:var(--status-violet)]/30 bg-[var(--status-violet-soft)] text-[var(--status-violet)]",
  amber:
    "border-[color:var(--status-amber)]/30 bg-[var(--status-amber-soft)] text-[var(--status-amber)]",
  orange:
    "border-[color:var(--status-orange)]/30 bg-[var(--status-orange-soft)] text-[var(--status-orange)]",
  green:
    "border-[color:var(--status-green)]/30 bg-[var(--status-green-soft)] text-[var(--status-green)]",
};

const glowToneClasses: Record<Tone, string> = {
  blue: "bg-accent/20",
  violet: "bg-[var(--status-violet)]/20",
  amber: "bg-[var(--status-amber)]/20",
  orange: "bg-[var(--status-orange)]/20",
  green: "bg-[var(--status-green)]/20",
};

const valueToneClasses: Record<Tone, string> = {
  blue: "text-accent",
  violet: "text-[var(--status-violet)]",
  amber: "text-[var(--status-amber)]",
  orange: "text-[var(--status-orange)]",
  green: "text-[var(--status-green)]",
};

interface Metric {
  icon: LucideIcon;
  label: string;
  tone: Tone;
  value: number;
}

export function OperationalSummary({
  repairs,
}: {
  repairs: RepairOrder[];
}) {
  const inactive: RepairStatus[] = [
    REPAIR_STATUS.DELIVERED,
    REPAIR_STATUS.CANCELLED,
    REPAIR_STATUS.UNREPAIRABLE,
  ];

  const count = (status: RepairStatus) =>
    repairs.filter((repair) => repair.status === status).length;

  const metrics: Metric[] = [
    {
      icon: Wrench,
      label: "Reparaciones activas",
      tone: "blue",
      value: repairs.filter(
        (repair) => !inactive.includes(repair.status),
      ).length,
    },
    {
      icon: ShieldCheck,
      label: "Esperando aprobación",
      tone: "violet",
      value: count(REPAIR_STATUS.WAITING_APPROVAL),
    },
    {
      icon: PackageSearch,
      label: "Esperando repuesto",
      tone: "amber",
      value: count(REPAIR_STATUS.WAITING_PART),
    },
    {
      icon: AlertTriangle,
      label: "Demoradas",
      tone: "orange",
      value: count(REPAIR_STATUS.DELAYED),
    },
    {
      icon: Clock3,
      label: "Listas para retirar",
      tone: "green",
      value: count(REPAIR_STATUS.READY_FOR_PICKUP),
    },
  ];

  return (
    <section aria-labelledby="operational-summary-title">
      <div className="mb-4">
        <p className="text-xs font-bold uppercase tracking-[0.14em] text-accent">
          Prioridades
        </p>

        <h2
          id="operational-summary-title"
          className="mt-1 text-lg font-bold text-app-text"
        >
          Resumen operativo
        </h2>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
        {metrics.map(({ icon: Icon, label, tone, value }) => (
          <article
            key={label}
            className="
              group
              relative
              min-w-0
              overflow-hidden
              rounded-2xl
              border
              border-app-border
              bg-app-card
              px-4
              py-4
              shadow-sm
              transition
              duration-200
              hover:-translate-y-0.5
              hover:border-app-text/15
              hover:shadow-md
            "
          >
            <div
              aria-hidden="true"
              className={`
                pointer-events-none
                absolute
                -right-10
                -top-12
                size-32
                rounded-full
                blur-3xl
                transition-opacity
                duration-300
                group-hover:opacity-100
                ${glowToneClasses[tone]}
              `}
            />

            <div className="relative flex min-h-[112px] flex-col">
              <div className="flex items-start justify-between gap-4">
                <span
                  className={`
                    grid
                    size-10
                    shrink-0
                    place-items-center
                    rounded-xl
                    border
                    ${iconToneClasses[tone]}
                  `}
                >
                  <Icon
                    aria-hidden="true"
                    className="size-[18px]"
                    strokeWidth={2}
                  />
                </span>

                <strong
                  className={`
                    text-2xl
                    font-bold
                    leading-none
                    tabular-nums
                    ${valueToneClasses[tone]}
                  `}
                >
                  {value}
                </strong>
              </div>

              <div className="mt-auto pt-5">
                <p className="text-sm font-semibold leading-5 text-app-text">
                  {label}
                </p>

                <div className="mt-3 h-px w-full bg-app-border/70" />

                <div
                  className={`
                    mt-2
                    h-0.5
                    w-10
                    rounded-full
                    opacity-70
                    ${glowToneClasses[tone]}
                  `}
                />
              </div>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}