import type { HTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "ui-card rounded-xl border border-line bg-surface-raised shadow-[0_2px_10px_rgb(var(--shadow-color)/7%)]",
        className,
      )}
      {...props}
    />
  );
}
