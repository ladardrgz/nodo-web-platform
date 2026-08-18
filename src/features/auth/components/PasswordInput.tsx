"use client";

import { Eye, EyeOff, LockKeyhole } from "lucide-react";
import { useState } from "react";

import { cn } from "@/lib/cn";

export function PasswordInput({ id, name, autoComplete, placeholder = "Ingresá tu contraseña", invalid = false, valid = false, ariaDescribedBy, onBlur, onValueChange }: { id: string; name: string; autoComplete: string; placeholder?: string; invalid?: boolean; valid?: boolean; ariaDescribedBy?: string; onBlur?: () => void; onValueChange?: (value: string) => void }) {
  const [visible, setVisible] = useState(false);
  return <div className="input-with-leading-and-trailing-icons relative"><LockKeyhole className="pointer-events-none absolute left-3 top-1/2 size-[18px] -translate-y-1/2 text-ink-muted" /><input aria-describedby={ariaDescribedBy} aria-invalid={invalid} autoComplete={autoComplete} className={cn("field-control", invalid && "field-control-invalid", valid && "field-control-valid")} id={id} name={name} onBlur={onBlur} onChange={(event) => onValueChange?.(event.target.value)} placeholder={placeholder} required type={visible ? "text" : "password"} /><button aria-label={visible ? "Ocultar contraseña" : "Mostrar contraseña"} className="absolute right-1.5 top-1/2 grid size-9 -translate-y-1/2 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft hover:text-ink" onClick={() => setVisible((value) => !value)} type="button">{visible ? <EyeOff className="size-[18px]" /> : <Eye className="size-[18px]" />}</button></div>;
}
