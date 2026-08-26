"use client";

import { ShieldAlert, X } from "lucide-react";
import { useActionState, useEffect, useState } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { updateProfileAccessAction } from "@/features/superadmin/actions";
import type { AppRole, OrganizationOption, ProfileStatus, UserListItem } from "@/features/superadmin/types";
import { requiredRoleConfirmation } from "@/features/superadmin/user-schema";
import type { ActionFeedbackState } from "@/lib/feedback/types";

const initialState: ActionFeedbackState = { status: "idle" };
const roleLabels: Record<AppRole, string> = { SUPERADMIN: "Superadmin", OWNER: "Propietario", CUSTOMER: "Cliente", TECHNICIAN: "Técnico" };
const statusLabels: Record<ProfileStatus, string> = { ACTIVE: "Activo", SUSPENDED: "Suspendido", DISABLED: "Inactivo" };

type AccessDraft = { role: AppRole; status: ProfileStatus; organizationId: string };

export function UserAccessForm({ user, organizations, currentUserId }: { user: UserListItem; organizations: OrganizationOption[]; currentUserId: string }) {
  const initialDraft: AccessDraft = { role: user.role, status: user.status, organizationId: user.organizationId };
  const [saved, setSaved] = useState(initialDraft);
  const [draft, setDraft] = useState(initialDraft);
  const [modalOpen, setModalOpen] = useState(false);
  const [confirmation, setConfirmation] = useState("");

  const [state, action] = useActionState(async (previousState: ActionFeedbackState, formData: FormData) => {
    const nextState = await updateProfileAccessAction(previousState, formData);
    setModalOpen(false);
    setConfirmation("");
    if (nextState.status === "success") setSaved(draft);
    else setDraft(saved);
    return nextState;
  }, initialState);

  const dirty = draft.role !== saved.role || draft.status !== saved.status || draft.organizationId !== saved.organizationId;
  const organizationRequired = draft.role !== "SUPERADMIN";
  const selectedOrganization = organizations.find((organization) => organization.id === draft.organizationId);
  const roleChanged = draft.role !== saved.role;
  const reducesOwnGlobalAccess = user.id === currentUserId && saved.role === "SUPERADMIN" && (draft.role !== "SUPERADMIN" || draft.status !== "ACTIVE");
  const requiredWord = reducesOwnGlobalAccess ? "MI CUENTA" : requiredRoleConfirmation(saved.role, draft.role) ?? "";
  const confirmationValid = !requiredWord || confirmation === requiredWord;

  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  useEffect(() => {
    if (!modalOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setModalOpen(false);
    };
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [modalOpen]);

  const openConfirmation = () => {
    if (!dirty || (organizationRequired && !selectedOrganization)) return;
    setConfirmation("");
    setModalOpen(true);
  };

  const modalTitle = reducesOwnGlobalAccess ? "Estás por modificar tu propio acceso global" : roleChanged && draft.role === "SUPERADMIN" ? "Estás por otorgar acceso de Superadministrador" : roleChanged && draft.role === "OWNER" ? "Estás por otorgar permisos de Propietario" : roleChanged && draft.role === "CUSTOMER" ? "Cambiar rol a Cliente" : "Confirmar cambio de estado";

  return (
    <div className="space-y-3">
      <ActionStateFeedback state={state} />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <label className="space-y-1.5"><span className="text-xs font-bold text-ink-secondary">Rol</span><select className="field-control" onChange={(event) => { const role = event.target.value as AppRole; setDraft((current) => ({ ...current, role, organizationId: role === "SUPERADMIN" ? "" : current.organizationId })); }} value={draft.role}><option value="SUPERADMIN">Superadmin</option><option value="OWNER">Propietario</option><option value="CUSTOMER">Cliente</option><option value="TECHNICIAN">Técnico</option></select></label>
        <label className="space-y-1.5"><span className="text-xs font-bold text-ink-secondary">Estado</span><select className="field-control" onChange={(event) => setDraft((current) => ({ ...current, status: event.target.value as ProfileStatus }))} value={draft.status}><option value="ACTIVE">Activo</option><option value="SUSPENDED">Suspendido</option><option value="DISABLED">Inactivo</option></select></label>
        <label className="space-y-1.5 sm:col-span-2 xl:col-span-1"><span className="text-xs font-bold text-ink-secondary">Organización</span><select className="field-control" disabled={!organizationRequired} onChange={(event) => setDraft((current) => ({ ...current, organizationId: event.target.value }))} value={draft.organizationId}><option value="">{organizationRequired ? "Seleccione una organización" : "Acceso global"}</option>{organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name} · {organization.slug}</option>)}</select></label>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3">{dirty ? <span className="text-xs font-bold text-warning">Cambios sin guardar</span> : <span className="text-xs text-ink-muted">Sin cambios pendientes</span>}<Button disabled={!dirty || (organizationRequired && !selectedOrganization)} onClick={openConfirmation} size="sm" variant="secondary">Guardar cambios</Button></div>

      {modalOpen ? <div className="fixed inset-0 z-[75] flex items-start justify-center overflow-y-auto bg-brand-surface/35 px-4 py-16 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setModalOpen(false); }}><div aria-labelledby={`access-modal-${user.id}`} aria-modal="true" className="w-full max-w-lg rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-4"><span className={`grid size-11 shrink-0 place-items-center rounded-xl ${requiredWord ? "bg-warning-soft text-warning" : "bg-accent-soft text-accent"}`}><ShieldAlert className="size-5" /></span><div className="flex-1"><h3 className="font-bold text-ink" id={`access-modal-${user.id}`}>{modalTitle}</h3><p className="mt-2 text-sm leading-6 text-ink-secondary">{roleChanged && draft.role === "SUPERADMIN" ? "Este usuario tendrá privilegios globales sobre Nodo y podrá acceder a funciones administrativas de toda la plataforma. Verificá cuidadosamente su identidad antes de continuar." : roleChanged && draft.role === "OWNER" ? "Este usuario podrá administrar la organización seleccionada y acceder a sus funciones administrativas." : "Revisá los datos antes de confirmar esta modificación de acceso."}</p></div><button aria-label="Cerrar confirmación" className="grid size-8 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft" onClick={() => setModalOpen(false)} type="button"><X className="size-4" /></button></div><dl className="mt-5 grid gap-2 rounded-lg bg-surface-soft p-4 text-sm"><div className="flex justify-between gap-4"><dt className="text-ink-muted">Usuario</dt><dd className="text-right font-semibold text-ink">{user.displayName}<span className="block text-xs font-normal text-ink-muted">{user.email}</span></dd></div><div className="flex justify-between gap-4"><dt className="text-ink-muted">Rol actual</dt><dd className="font-semibold text-ink">{roleLabels[saved.role]}</dd></div><div className="flex justify-between gap-4"><dt className="text-ink-muted">Nuevo rol</dt><dd className="font-semibold text-ink">{roleLabels[draft.role]}</dd></div><div className="flex justify-between gap-4"><dt className="text-ink-muted">Estado</dt><dd className="font-semibold text-ink">{statusLabels[draft.status]}</dd></div><div className="flex justify-between gap-4"><dt className="text-ink-muted">Organización</dt><dd className="font-semibold text-ink">{draft.role === "SUPERADMIN" ? "Global" : selectedOrganization?.name ?? "Sin organización"}</dd></div></dl><form action={action} className="mt-5 space-y-4"><input name="userId" type="hidden" value={user.id} /><input name="role" type="hidden" value={draft.role} /><input name="status" type="hidden" value={draft.status} /><input name="organizationId" type="hidden" value={draft.organizationId} />{requiredWord ? <label className="block space-y-2"><span className="text-sm font-semibold text-ink">Escribí <strong>{requiredWord}</strong> para continuar</span><input autoComplete="off" className="field-control" name="confirmation" onChange={(event) => setConfirmation(event.target.value)} value={confirmation} /></label> : <input name="confirmation" type="hidden" value="CONFIRM" />}<div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button onClick={() => setModalOpen(false)} variant="secondary">Cancelar</Button><SubmitButton disabled={!confirmationValid} label={requiredWord ? "Confirmar cambio de rol" : "Confirmar"} pendingLabel="Guardando cambios…" /></div></form></div></div> : null}
    </div>
  );
}
