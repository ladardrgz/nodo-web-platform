import { cn } from "@/lib/cn";

interface StatusBadgeProps {
  status: string;
  label?: string;
  compact?: boolean;
}

export function StatusBadge({ status, label, compact = false }: StatusBadgeProps) {
  void compact;
  const color = status === "DELIVERED" ? "bg-slate-100 text-slate-700 ring-slate-200" : status === "CANCELLED" ? "bg-rose-50 text-rose-800 ring-rose-200" : "bg-accent-soft text-accent ring-accent/20";

  return (
    <span
      className={cn(
        "inline-flex w-fit items-center gap-2 rounded-full px-2.5 py-1 text-xs font-bold ring-1 ring-inset",
        color,
      )}
    >
      <span className="size-1.5 rounded-full bg-current" />
      {label ?? status.replaceAll("_", " ")}
    </span>
  );
}
