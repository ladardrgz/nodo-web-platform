"use client";

import { PauseCircle, PlayCircle, X } from "lucide-react";
import { useActionState, useEffect, useState } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { setOrganizationStatusAction } from "@/features/superadmin/organization-actions";
import type { ActionFeedbackState } from "@/lib/feedback/types";

const initialState: ActionFeedbackState = { status: "idle" };

export function OrganizationStatusAction({ id, name, status }: { id: string; name: string; status: "ACTIVE" | "SUSPENDED" }) {
  const [open, setOpen] = useState(false);
  const [confirmation, setConfirmation] = useState("");
  const target = status === "ACTIVE" ? "SUSPENDED" : "ACTIVE";
  const [state, action] = useActionState(async (previous: ActionFeedbackState, formData: FormData) => {
    const next = await setOrganizationStatusAction(previous, formData);
    if (next.status === "success") setOpen(false);
    return next;
  }, initialState);
  useEffect(() => {
    if (!open) return;
    const close = (event: KeyboardEvent) => { if (event.key === "Escape") setOpen(false); };
    document.addEventListener("keydown", close);
    return () => document.removeEventListener("keydown", close);
  }, [open]);
  return <><ActionStateFeedback state={state} /><Button onClick={() => { setConfirmation(""); setOpen(true); }} variant={status === "ACTIVE" ? "danger" : "secondary"}>{status === "ACTIVE" ? <PauseCircle className="size-4" /> : <PlayCircle className="size-4" />}{status === "ACTIVE" ? "Suspender organización" : "Reactivar organización"}</Button>{open ? <div className="fixed inset-0 z-[80] flex items-start justify-center overflow-y-auto bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setOpen(false); }}><div aria-modal="true" className="w-full max-w-lg rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-3"><div><h2 className="font-bold text-ink">{status === "ACTIVE" ? "Suspender organización" : "¿Querés reactivar esta organización?"}</h2><p className="mt-2 text-sm leading-6 text-ink-secondary">{status === "ACTIVE" ? "Los usuarios de esta organización perderán temporalmente el acceso operativo. Sus datos permanecerán conservados." : "Los usuarios recuperarán el acceso que corresponda a su rol y configuración."}</p></div><button aria-label="Cerrar" className="grid size-8 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft" onClick={() => setOpen(false)}><X className="size-4" /></button></div><dl className="mt-5 space-y-2 rounded-lg bg-surface-soft p-4 text-sm"><div className="flex justify-between gap-4"><dt className="text-ink-muted">Organización</dt><dd className="font-semibold text-ink">{name}</dd></div><div className="flex justify-between gap-4"><dt className="text-ink-muted">Estado actual</dt><dd className="font-semibold text-ink">{status === "ACTIVE" ? "Activa" : "Suspendida"}</dd></div><div className="flex justify-between gap-4"><dt className="text-ink-muted">Nuevo estado</dt><dd className="font-semibold text-ink">{target === "ACTIVE" ? "Activa" : "Suspendida"}</dd></div></dl><form action={action} className="mt-5 space-y-4"><input name="organizationId" type="hidden" value={id} /><input name="status" type="hidden" value={target} />{target === "SUSPENDED" ? <label className="block space-y-2"><span className="text-sm font-semibold text-ink">Escribí <strong>SUSPENDER</strong> para continuar</span><input autoComplete="off" className="field-control" name="confirmation" onChange={(event) => setConfirmation(event.target.value)} value={confirmation} /></label> : <input name="confirmation" type="hidden" value="CONFIRM" />}<div className="flex justify-end gap-2"><Button onClick={() => setOpen(false)} variant="secondary">Cancelar</Button><SubmitButton disabled={target === "SUSPENDED" && confirmation !== "SUSPENDER"} label={target === "SUSPENDED" ? "Confirmar suspensión" : "Confirmar reactivación"} pendingLabel="Aplicando cambio…" /></div></form></div></div> : null}</>;
}
