"use client";

import { X } from "lucide-react";
import type { InputHTMLAttributes, ReactNode } from "react";

import { cn } from "@/lib/cn";

interface IconInputProps extends InputHTMLAttributes<HTMLInputElement> {
  leadingIcon?: ReactNode;
  trailingAdornment?: ReactNode;
  onClear?: () => void;
  clearLabel?: string;
}

export function IconInput({ leadingIcon, trailingAdornment, onClear, clearLabel = "Limpiar campo", className, value, ...props }: IconInputProps) {
  const hasClear = Boolean(onClear && String(value ?? ""));
  const hasTrailing = hasClear || Boolean(trailingAdornment);
  const wrapperClass = leadingIcon && hasTrailing ? "input-with-leading-and-trailing-icons" : leadingIcon ? "input-with-leading-icon" : hasTrailing ? "input-with-trailing-icon" : undefined;
  return (
    <span className={cn("relative block", wrapperClass)}>
      {leadingIcon ? <span aria-hidden className="pointer-events-none absolute left-3.5 top-1/2 z-10 grid size-5 -translate-y-1/2 place-items-center text-ink-muted">{leadingIcon}</span> : null}
      <input className={cn("field-control", className)} value={value} {...props} />
      {hasClear ? <button aria-label={clearLabel} className="absolute right-1.5 top-1/2 z-10 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-ink-muted transition hover:bg-surface-soft hover:text-ink" onClick={onClear} type="button"><X className="size-4" /></button> : trailingAdornment ? <span className="pointer-events-none absolute right-3.5 top-1/2 z-10 grid size-5 -translate-y-1/2 place-items-center text-ink-muted">{trailingAdornment}</span> : null}
    </span>
  );
}
