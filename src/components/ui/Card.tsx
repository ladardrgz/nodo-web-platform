import type { HTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "ui-card rounded-xl border border-line bg-surface-raised shadow-[0_3px_14px_rgb(var(--shadow-color)/10%)]",
        className,
      )}
      {...props}
    />
  );
}
