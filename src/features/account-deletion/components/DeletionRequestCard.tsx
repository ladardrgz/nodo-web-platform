"use client";

import { AlertTriangle, Trash2, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useId, useRef, useState } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { requestDeletionAction } from "@/features/account-deletion/actions";
import { initialDeletionState, type DeletionSubject } from "@/features/account-deletion/types";

export function DeletionRequestCard({ subject }: { subject: DeletionSubject }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [state, action, pending] = useActionState(requestDeletionAction, initialDeletionState);
  const titleId = useId();
  const closeButton = useRef<HTMLButtonElement>(null);
  const router = useRouter();
  const organization = subject === "ORGANIZATION";

  useEffect(() => {
    if (!open) return;
    closeButton.current?.focus();
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape" && !pending) setOpen(false); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, pending]);

  useEffect(() => {
    if (!state.completed) return;
    const timer = window.setTimeout(() => router.push("/account-pending-deletion"), 900);
    return () => window.clearTimeout(timer);
  }, [router, state]);

  return <>
    <ActionStateFeedback state={state} />
    <div className="flex items-start gap-3">
      <AlertTriangle className="mt-0.5 size-5 shrink-0 text-warning" />
      <div className="min-w-0 flex-1">
        <h2 className="font-bold text-primary">{organization ? "Dar de baja la organización" : "Dar de baja mi cuenta"}</h2>
        <p className="mt-1 text-sm leading-6 text-muted">La baja desactiva el acceso durante 30 días antes de iniciar la eliminación definitiva de los datos que puedan eliminarse.</p>
        {state.blockers?.length ? <div className="mt-4 rounded-lg border border-warning/30 bg-warning-soft p-3" role="alert"><p className="text-sm font-bold text-warning">Primero tenés que resolver:</p><ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-primary">{state.blockers.map((blocker) => <li key={blocker.code}>{blocker.message}</li>)}</ul></div> : null}
        <Button className="mt-4" onClick={() => setOpen(true)} variant="danger"><Trash2 className="size-4" />{organization ? "Dar de baja la organización" : "Dar de baja mi cuenta"}</Button>
      </div>
    </div>
    {open ? <div className="fixed inset-0 z-[90] flex items-start justify-center overflow-y-auto bg-brand-surface/40 px-4 py-16 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target && !pending) setOpen(false); }}>
      <div aria-labelledby={titleId} aria-modal="true" className="w-full max-w-lg rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog">
        <div className="flex items-start justify-between gap-4"><div><h2 className="text-lg font-bold text-primary" id={titleId}>{organization ? "Dar de baja la organización" : "Dar de baja mi cuenta"}</h2><p className="mt-2 text-sm leading-6 text-muted">Tu cuenta quedará desactivada y podrás recuperarla durante 30 días. Los comprobantes y reparaciones ya realizadas permanecerán en el historial correspondiente.</p></div><button aria-label="Cerrar confirmación" className="grid size-8 shrink-0 place-items-center rounded-lg text-muted hover:bg-surface-soft hover:text-primary" disabled={pending} onClick={() => setOpen(false)} ref={closeButton} type="button"><X className="size-4" /></button></div>
        <form action={action} className="mt-5 space-y-4"><input name="subject" type="hidden" value={subject} /><label className="block"><span className="text-sm font-semibold text-primary">Motivo de la baja</span><textarea className="field-control mt-2 min-h-24 resize-y" maxLength={300} minLength={3} name="reason" onChange={(event) => setReason(event.target.value)} placeholder="Contanos brevemente el motivo" required value={reason} /><span className="mt-1 block text-xs text-muted">Se guardará en auditoría junto con el usuario, la fecha y el estado de la solicitud.</span></label>{state.blockers?.length ? <div className="rounded-lg border border-warning/30 bg-warning-soft p-3" role="alert"><p className="text-sm font-bold text-warning">No podemos completar la baja todavía:</p><ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-primary">{state.blockers.map((blocker) => <li key={blocker.code}>{blocker.message}</li>)}</ul></div> : null}<div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button disabled={pending} onClick={() => setOpen(false)} variant="secondary">Cancelar</Button><SubmitButton disabled={reason.trim().length < 3} label="Dar de baja" pendingLabel="Solicitando baja…" variant="danger" /></div></form>
      </div>
    </div> : null}
  </>;
}
