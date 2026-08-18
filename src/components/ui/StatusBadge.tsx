import { repairStatusConfig } from "@/config/repair-status";
import type { RepairStatus } from "@/features/repairs/types";
import { cn } from "@/lib/cn";

interface StatusBadgeProps {
  status: RepairStatus;
  compact?: boolean;
}

export function StatusBadge({ status, compact = false }: StatusBadgeProps) {
  const definition = repairStatusConfig[status];

  return (
    <span
      className={cn(
        "inline-flex w-fit items-center gap-2 rounded-full px-2.5 py-1 text-xs font-bold ring-1 ring-inset",
        definition.badgeClassName,
      )}
    >
      <span className={cn("size-1.5 rounded-full", definition.dotClassName)} />
      {compact ? definition.shortLabel : definition.label}
    </span>
  );
}
