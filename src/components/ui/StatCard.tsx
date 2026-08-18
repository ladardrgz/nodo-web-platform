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
  blue: "bg-blue-50 text-blue-700",
  violet: "bg-violet-50 text-violet-700",
  amber: "bg-amber-50 text-amber-700",
  orange: "bg-orange-50 text-orange-700",
  green: "bg-emerald-50 text-emerald-700",
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
        <span className={`grid size-10 place-items-center rounded-lg ${toneClasses[tone]}`}>
          {icon}
        </span>
      </div>
      <p className="mt-3 text-xs leading-5 text-muted">{description}</p>
    </Card>
  );
}
