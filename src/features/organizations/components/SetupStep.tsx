import { Check, type LucideIcon } from "lucide-react";

import { cn } from "@/lib/cn";

export type SetupStepStatus = "PENDING" | "ACTIVE" | "COMPLETED";

export interface SetupStepDefinition {
  id: string;
  number: string;
  title: string;
  description: string;
  icon: LucideIcon;
}

interface SetupStepProps {
  compact?: boolean;
  enabled: boolean;
  onSelect: () => void;
  status: SetupStepStatus;
  step: SetupStepDefinition;
}

const statusLabel: Record<SetupStepStatus, string> = {
  ACTIVE: "Paso actual",
  COMPLETED: "Completado",
  PENDING: "Pendiente",
};

export function SetupStep({ compact = false, enabled, onSelect, status, step }: SetupStepProps) {
  const Icon = step.icon;
  const active = status === "ACTIVE";
  const completed = status === "COMPLETED";

  return (
    <button
      aria-current={active ? "step" : undefined}
      aria-disabled={!enabled}
      aria-label={`${step.number} ${step.title}. ${statusLabel[status]}`}
      className={cn(
        "group relative flex min-w-0 text-left focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent",
        compact ? "flex-col items-center gap-1.5 rounded-lg px-1 py-2" : "w-full items-center gap-3 rounded-xl p-3",
        enabled && !active ? "cursor-pointer hover:bg-surface-soft" : "cursor-default",
      )}
      disabled={!enabled || active}
      onClick={onSelect}
      type="button"
    >
      <span
        className={cn(
          "relative z-10 grid shrink-0 place-items-center rounded-full border-2 font-bold transition-colors",
          compact ? "size-8 text-[11px]" : "size-11 text-xs",
          active && "border-accent bg-accent-button text-white shadow-[0_0_0_4px_var(--accent-soft)]",
          completed && "border-success bg-success-soft text-success",
          status === "PENDING" && "border-line-strong bg-surface text-ink-muted",
        )}
      >
        {completed ? <Check aria-hidden="true" className={compact ? "size-4" : "size-5"} /> : step.number}
      </span>

      {compact ? (
        <span className={cn("max-w-full truncate text-[10px] font-semibold", active ? "text-ink" : "text-ink-muted")}>
          {step.title}
        </span>
      ) : (
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <Icon aria-hidden="true" className={cn("size-4", active ? "text-accent" : completed ? "text-success" : "text-ink-muted")} />
            <strong className={cn("text-sm", active ? "text-ink" : "text-ink-secondary")}>{step.title}</strong>
          </span>
          <span className="mt-1 block text-xs text-ink-muted">{statusLabel[status]}</span>
        </span>
      )}
    </button>
  );
}
