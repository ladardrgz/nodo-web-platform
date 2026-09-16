"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { cancelDeletionAction } from "@/features/account-deletion/actions";
import { initialDeletionState, type PendingDeletion } from "@/features/account-deletion/types";

export function PendingDeletionPanel({ request }: { request: PendingDeletion }) {
  const [state, action] = useActionState(cancelDeletionAction, initialDeletionState);
  const router = useRouter();
  useEffect(() => {
    if (!state.completed) return;
    const destination = request.subject_type === "ORGANIZATION" ? "/dashboard" : "/portal";
    const timer = window.setTimeout(() => router.push(destination), 700);
    return () => window.clearTimeout(timer);
  }, [request.subject_type, router, state]);

  const deadline = new Intl.DateTimeFormat("es-AR", { dateStyle: "long", timeZone: "America/Argentina/Buenos_Aires" }).format(new Date(request.scheduled_for));
  return <>
    <ActionStateFeedback state={state} />
    <div className="rounded-xl border border-warning/30 bg-warning-soft p-5 sm:p-7">
      <p className="text-xs font-bold uppercase tracking-[0.16em] text-warning">Baja pendiente</p>
      <h1 className="mt-2 text-2xl font-bold text-primary">{request.subject_type === "ORGANIZATION" ? "La organización está desactivada" : "Tu cuenta está desactivada"}</h1>
      <p className="mt-3 max-w-2xl text-sm leading-6 text-muted">Podés recuperar el acceso hasta el {deadline}. Después de esa fecha se eliminarán los datos que puedan borrarse; los comprobantes, reparaciones finalizadas y la auditoría permanecerán en el historial correspondiente.</p>
      <dl className="mt-5 grid gap-3 rounded-lg bg-surface-raised p-4 text-sm sm:grid-cols-2"><div><dt className="text-muted">Estado</dt><dd className="mt-1 font-semibold text-primary">Pendiente de eliminación</dd></div><div><dt className="text-muted">Motivo registrado</dt><dd className="mt-1 font-semibold text-primary">{request.reason}</dd></div></dl>
      <form action={action} className="mt-5"><SubmitButton label="Reactivar acceso" pendingLabel="Reactivando…" /></form>
    </div>
  </>;
}
