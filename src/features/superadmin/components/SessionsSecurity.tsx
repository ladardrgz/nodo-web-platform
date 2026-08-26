"use client";

import { Laptop, LogOut, X } from "lucide-react";
import { useActionState, useEffect, useState } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { revokeOtherSessionsAction } from "@/features/superadmin/security-actions";
import type { ActionFeedbackState } from "@/lib/feedback/types";

const initialState: ActionFeedbackState = { status: "idle" };

export function SessionsSecurity({ lastAccess }: { lastAccess: string | null }) {
  const [open, setOpen] = useState(false);
  const [state, action] = useActionState(async (previous: ActionFeedbackState, formData: FormData) => {
    const next = await revokeOtherSessionsAction(previous, formData);
    if (next.status === "success") setOpen(false);
    return next;
  }, initialState);
  useEffect(() => {
    if (!open) return;
    const close = (event: KeyboardEvent) => { if (event.key === "Escape") setOpen(false); };
    document.addEventListener("keydown", close);
    return () => document.removeEventListener("keydown", close);
  }, [open]);

  return <section className="rounded-xl border border-line bg-surface-raised p-5 sm:p-6"><ActionStateFeedback state={state} /><div className="flex items-start gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><Laptop className="size-5" /></span><div><div className="flex items-center gap-2"><h2 className="font-bold text-ink">Sesiones</h2><ContextHelp label="Ayuda sobre sesiones" title="¿Qué sesiones puede mostrar Nodo?">Supabase permite revocar las demás sesiones, pero no expone una lista fiable de navegador, dispositivo, ubicación o IP mediante la API pública. Por eso Nodo muestra únicamente la sesión actual y no inventa datos.</ContextHelp></div><p className="mt-1 text-sm text-ink-muted">Controlá el acceso activo a tu cuenta.</p></div></div><div className="mt-5 rounded-lg bg-surface-soft p-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><p className="font-semibold text-ink">Sesión actual</p><p className="mt-1 text-xs text-ink-muted">Último acceso auditado: {lastAccess ?? "Sin un evento fiable todavía"}</p></div><span className="rounded-full bg-success-soft px-2.5 py-1 text-xs font-bold text-success">Actual</span></div></div><Button className="mt-4" onClick={() => setOpen(true)} variant="secondary"><LogOut className="size-4" />Cerrar las demás sesiones</Button>{open ? <div className="fixed inset-0 z-[80] flex items-start justify-center bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setOpen(false); }}><div aria-modal="true" className="w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold text-ink">Cerrar las demás sesiones</h3><p className="mt-2 text-sm leading-6 text-ink-secondary">Se cerrarán las demás sesiones asociadas a tu cuenta. Tu sesión actual permanecerá activa.</p></div><button aria-label="Cerrar" className="grid size-8 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft" onClick={() => setOpen(false)}><X className="size-4" /></button></div><form action={action} className="mt-5 flex justify-end gap-2"><Button onClick={() => setOpen(false)} variant="secondary">Cancelar</Button><SubmitButton label="Cerrar demás sesiones" pendingLabel="Cerrando sesiones…" /></form></div></div> : null}</section>;
}
