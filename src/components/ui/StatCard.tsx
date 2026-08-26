import type { ReactNode } from "react";

import { Card } from "@/components/ui/Card";

interface StatCardProps {
  label: string;
  value: number;
  description: string;
  icon: ReactNode;
  tone?: "blue" | "violet" | "amber" | "orange" | "green";
}

const toneClasses = {
  blue: "bg-accent-soft text-accent ring-accent/15",
  violet: "bg-[var(--status-violet-soft)] text-[var(--status-violet)] ring-[color:var(--status-violet)]/15",
  amber: "bg-[var(--status-amber-soft)] text-[var(--status-amber)] ring-[color:var(--status-amber)]/15",
  orange: "bg-[var(--status-orange-soft)] text-[var(--status-orange)] ring-[color:var(--status-orange)]/15",
  green: "bg-[var(--status-green-soft)] text-[var(--status-green)] ring-[color:var(--status-green)]/15",
};

export function StatCard({
  label,
  value,
  description,
  icon,
  tone = "blue",
}: StatCardProps) {
  return (
    <Card className="p-4 sm:p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-muted">{label}</p>
          <p className="mt-2 text-3xl font-bold text-primary">{value}</p>
        </div>
        <span className={`grid size-10 place-items-center rounded-lg ring-1 ring-inset ${toneClasses[tone]}`}>
          {icon}
        </span>
      </div>
      <p className="mt-3 text-xs leading-5 text-muted">{description}</p>
    </Card>
  );
}
