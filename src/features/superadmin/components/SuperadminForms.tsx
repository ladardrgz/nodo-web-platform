"use client";

import { useActionState } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { createOrganizationAction, inviteUserAction, updateProfileAccessAction } from "@/features/superadmin/actions";
import type { ActionFeedbackState } from "@/lib/feedback/types";

const initialState: ActionFeedbackState = { status: "idle" };
type OrganizationOption = { id: string; name: string };

export function CreateOrganizationForm() {
  const [state, action] = useActionState(createOrganizationAction, initialState);
  return (
    <form action={action} className="mt-4 space-y-3">
      <ActionStateFeedback state={state} />
      <input aria-label="Nombre de la organización" className="field-control" minLength={2} name="name" placeholder="Nombre de la organización" required />
      <input aria-label="Slug de la organización" className="field-control" name="slug" pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="nombre-organizacion" required />
      <SubmitButton className="w-full" label="Crear organización" pendingLabel="Creando organización…" />
    </form>
  );
}

export function InviteUserForm({ organizations }: { organizations: OrganizationOption[] }) {
  const [state, action] = useActionState(inviteUserAction, initialState);
  return (
    <form action={action} className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-5">
      <ActionStateFeedback state={state} />
      <input aria-label="Nombre" className="field-control" minLength={2} name="firstName" placeholder="Nombre" required />
      <input aria-label="Apellido" className="field-control" minLength={2} name="lastName" placeholder="Apellido" required />
      <input aria-label="Correo electrónico" className="field-control" name="email" placeholder="correo@dominio.com" required type="email" />
      <select aria-label="Rol" className="field-control" name="role"><option value="OWNER">Propietario</option><option value="CUSTOMER">Cliente</option></select>
      <select aria-label="Organización" className="field-control" name="organizationId" required><option value="">Organización</option>{organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select>
      <SubmitButton className="md:col-span-2 xl:col-span-5" label="Enviar enlace de activación" pendingLabel="Enviando invitación…" />
    </form>
  );
}

export function ProfileAccessForm({ profile, organizations }: { profile: { id: string; role: string; status: string; organizationId: string }; organizations: OrganizationOption[] }) {
  const [state, action] = useActionState(updateProfileAccessAction, initialState);
  return (
    <form action={action} className="flex gap-2">
      <ActionStateFeedback state={state} />
      <input name="userId" type="hidden" value={profile.id} />
      <select aria-label="Rol" className="field-control min-w-36" defaultValue={profile.role} name="role"><option value="SUPERADMIN">Superadmin</option><option value="OWNER">Propietario</option><option value="CUSTOMER">Cliente</option></select>
      <select aria-label="Estado" className="field-control min-w-36" defaultValue={profile.status} name="status"><option value="ACTIVE">Activo</option><option value="SUSPENDED">Suspendido</option><option value="DISABLED">Deshabilitado</option></select>
      <select aria-label="Organización" className="field-control min-w-44" defaultValue={profile.organizationId} name="organizationId"><option value="">Sin organización</option>{organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select>
      <SubmitButton label="Guardar" pendingLabel="Guardando…" size="sm" variant="secondary" />
    </form>
  );
}
