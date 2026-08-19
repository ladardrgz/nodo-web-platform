"use client";

import { LogOut } from "lucide-react";
import { useFormStatus } from "react-dom";

import { NodoLoader } from "@/components/ui/NodoLoader";
import { cn } from "@/lib/cn";

export function LogoutSubmitButton({ className, compact = false, label = "Cerrar sesión" }: { className?: string; compact?: boolean; label?: string }) {
  const { pending } = useFormStatus();
  return (
    <button aria-busy={pending || undefined} aria-label={label} className={cn("inline-flex items-center justify-center gap-2 disabled:pointer-events-none disabled:opacity-60", className)} disabled={pending} type="submit">
      {pending ? <NodoLoader size="sm" /> : <LogOut className="size-4" />}
      {compact ? null : pending ? "Cerrando…" : label}
    </button>
  );
}
