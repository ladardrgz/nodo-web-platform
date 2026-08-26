"use client";

import { useActionState, useRef, useState, type FormEvent } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { useToast } from "@/components/feedback/ToastProvider";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { createOrganizationAction, inviteUserAction } from "@/features/superadmin/actions";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import {
  normalizeOrganizationName,
  normalizeOrganizationNameForComparison,
  organizationNameSchema,
  organizationSlugSchema,
  type OrganizationCreationState,
} from "@/features/superadmin/organization-schema";
import type { OrganizationOption } from "@/features/superadmin/types";
import {
  invitationEmailSchema,
  inviteUserSchema,
  normalizePersonName,
  personNameSchema,
  type InvitationState,
} from "@/features/superadmin/user-schema";
import { cn } from "@/lib/cn";

const organizationInitialState: OrganizationCreationState = { status: "idle" };
const invitationInitialState: InvitationState = { status: "idle" };

function localOrganizationError(field: "name" | "slug", value: string, organizations: OrganizationOption[]): string | undefined {
  const result = field === "name" ? organizationNameSchema.safeParse(value) : organizationSlugSchema.safeParse(value);
  if (!result.success) return result.error.issues[0]?.message;
  if (field === "name" && organizations.some((organization) => normalizeOrganizationNameForComparison(organization.name) === normalizeOrganizationNameForComparison(result.data))) return "Este nombre ya está siendo utilizado por otra organización.";
  if (field === "slug" && organizations.some((organization) => organization.slug?.toLowerCase() === result.data)) return "Este identificador ya está ocupado.";
  return undefined;
}

export function CreateOrganizationForm({ organizations }: { organizations: OrganizationOption[] }) {
  const [values, setValues] = useState({ name: "", slug: "" });
  const [touched, setTouched] = useState({ name: false, slug: false });
  const [submitted, setSubmitted] = useState(false);
  const [editedSinceResponse, setEditedSinceResponse] = useState<Set<"name" | "slug">>(new Set());
  const emptyToastShown = useRef(false);
  const { toast } = useToast();

  const [state, action] = useActionState(async (previousState: OrganizationCreationState, formData: FormData) => {
    const nextState = await createOrganizationAction(previousState, formData);
    setEditedSinceResponse(new Set());
    if (nextState.status === "success") {
      setValues({ name: "", slug: "" });
      setTouched({ name: false, slug: false });
      setSubmitted(false);
      emptyToastShown.current = false;
    }
    return nextState;
  }, organizationInitialState);

  const nameClientError = touched.name || submitted ? localOrganizationError("name", values.name, organizations) : undefined;
  const slugClientError = touched.slug || submitted ? localOrganizationError("slug", values.slug, organizations) : undefined;
  const nameError = nameClientError ?? (!editedSinceResponse.has("name") ? state.fieldErrors?.name?.[0] : undefined);
  const slugError = slugClientError ?? (!editedSinceResponse.has("slug") ? state.fieldErrors?.slug?.[0] : undefined);

  function update(field: "name" | "slug", value: string) {
    setValues((current) => ({ ...current, [field]: field === "slug" ? value.toLowerCase() : value }));
    setEditedSinceResponse((current) => new Set(current).add(field));
    if (value.trim()) emptyToastShown.current = false;
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    setSubmitted(true);
    setTouched({ name: true, slug: true });
    const nextNameError = localOrganizationError("name", values.name, organizations);
    const nextSlugError = localOrganizationError("slug", values.slug, organizations);
    if (!nextNameError && !nextSlugError) return;
    event.preventDefault();
    if ((!values.name.trim() || !values.slug.trim()) && !emptyToastShown.current) {
      emptyToastShown.current = true;
      toast({ variant: "warning", title: "Completá los campos obligatorios antes de continuar." });
    }
  }

  return (
    <form action={action} className="mt-5 max-w-xl space-y-5" noValidate onSubmit={handleSubmit}>
      <ActionStateFeedback state={state} />
      <div className="space-y-2">
        <label className="block text-sm font-semibold text-primary" htmlFor="organization-name">Razón social / nombre <span className="text-danger">*</span></label>
        <input aria-describedby="organization-name-help organization-name-error" aria-invalid={Boolean(nameError)} className={cn("field-control", nameError ? "field-control-invalid" : (touched.name || submitted) && values.name.trim() ? "field-control-valid" : undefined)} id="organization-name" maxLength={120} name="name" onBlur={() => { setTouched((current) => ({ ...current, name: true })); setValues((current) => ({ ...current, name: normalizeOrganizationName(current.name) })); }} onChange={(event) => update("name", event.target.value)} placeholder="Ingrese el nombre de la razón de su empresa" required value={values.name} />
        {nameError ? <p className="text-sm font-medium text-danger" id="organization-name-error">{nameError}</p> : <p className="text-xs leading-5 text-muted" id="organization-name-help">Nombre legal o comercial que identificará a esta organización.</p>}
      </div>
      <div className="space-y-2">
        <label className="block text-sm font-semibold text-primary" htmlFor="organization-slug">Usuario / identificador de organización <span className="text-danger">*</span></label>
        <input aria-describedby="organization-slug-help organization-slug-error" aria-invalid={Boolean(slugError)} autoCapitalize="none" autoCorrect="off" className={cn("field-control font-mono", slugError ? "field-control-invalid" : (touched.slug || submitted) && values.slug ? "field-control-valid" : undefined)} id="organization-slug" maxLength={80} name="slug" onBlur={() => setTouched((current) => ({ ...current, slug: true }))} onChange={(event) => update("slug", event.target.value)} placeholder="usuario-de-la-organizacion" required spellCheck={false} value={values.slug} />
        {slugError ? <p className="text-sm font-medium text-danger" id="organization-slug-error">{slugError}</p> : <p className="text-xs leading-5 text-muted" id="organization-slug-help">Identificador único. Ejemplo de acceso: <strong className="font-mono text-primary">{values.slug || "nodo"}</strong></p>}
      </div>
      <SubmitButton className="w-full sm:w-auto" label="Crear organización" pendingLabel="Creando organización…" />
    </form>
  );
}

type InvitationField = "firstName" | "lastName" | "email" | "role" | "organizationId";
type InvitationValues = Record<InvitationField, string>;

function localInvitationError(field: InvitationField, value: string, organizations: OrganizationOption[], existingEmails: string[]) {
  if (field === "firstName" || field === "lastName") {
    const result = personNameSchema.safeParse(value);
    return result.success ? undefined : result.error.issues[0]?.message;
  }
  if (field === "email") {
    const result = invitationEmailSchema.safeParse(value);
    if (!result.success) return result.error.issues[0]?.message;
    if (existingEmails.some((email) => email.toLowerCase() === result.data)) return "Este correo ya tiene una cuenta o una invitación pendiente.";
    return undefined;
  }
  if (field === "role") return inviteUserSchema.shape.role.safeParse(value).success ? undefined : "Seleccione el tipo de usuario.";
  return organizations.some((organization) => organization.id === value) ? undefined : "Seleccione la organización a la que pertenecerá.";
}

export function InviteUserForm({ organizations, existingEmails }: { organizations: OrganizationOption[]; existingEmails: string[] }) {
  const [values, setValues] = useState<InvitationValues>({ firstName: "", lastName: "", email: "", role: "", organizationId: "" });
  const [touched, setTouched] = useState<Set<InvitationField>>(new Set());
  const [submitted, setSubmitted] = useState(false);
  const [editedSinceResponse, setEditedSinceResponse] = useState<Set<InvitationField>>(new Set());
  const emptyToastShown = useRef(false);
  const { toast } = useToast();

  const [state, action] = useActionState(async (previousState: InvitationState, formData: FormData) => {
    const nextState = await inviteUserAction(previousState, formData);
    setEditedSinceResponse(new Set());
    if (nextState.status === "success") {
      setValues({ firstName: "", lastName: "", email: "", role: "", organizationId: "" });
      setTouched(new Set());
      setSubmitted(false);
      emptyToastShown.current = false;
    }
    return nextState;
  }, invitationInitialState);

  const errorFor = (field: InvitationField) => {
    const clientError = touched.has(field) || submitted ? localInvitationError(field, values[field], organizations, existingEmails) : undefined;
    return clientError ?? (!editedSinceResponse.has(field) ? state.fieldErrors?.[field]?.[0] : undefined);
  };

  const update = (field: InvitationField, value: string) => {
    setValues((current) => ({ ...current, [field]: field === "email" ? value.toLowerCase() : value }));
    setEditedSinceResponse((current) => new Set(current).add(field));
    if (value.trim()) emptyToastShown.current = false;
  };

  const blur = (field: InvitationField) => {
    setTouched((current) => new Set(current).add(field));
    if (field === "firstName" || field === "lastName") setValues((current) => ({ ...current, [field]: normalizePersonName(current[field]) }));
  };

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    setSubmitted(true);
    setTouched(new Set<InvitationField>(["firstName", "lastName", "email", "role", "organizationId"]));
    const fields: InvitationField[] = ["firstName", "lastName", "email", "role", "organizationId"];
    if (fields.every((field) => !localInvitationError(field, values[field], organizations, existingEmails))) return;
    event.preventDefault();
    if (fields.some((field) => !values[field].trim()) && !emptyToastShown.current) {
      emptyToastShown.current = true;
      toast({ variant: "warning", title: "Completá los campos obligatorios antes de continuar." });
    }
  };

  return (
    <form action={action} className="mt-5 max-w-3xl space-y-5" noValidate onSubmit={handleSubmit}>
      <ActionStateFeedback state={state} />
      <div className="grid gap-5 md:grid-cols-2">
        <div className="space-y-2"><label className="block text-sm font-semibold text-ink" htmlFor="invite-first-name">Nombre <span className="text-danger">*</span></label><input aria-describedby={errorFor("firstName") ? "invite-first-name-error" : undefined} aria-invalid={Boolean(errorFor("firstName"))} className={cn("field-control", errorFor("firstName") && "field-control-invalid")} id="invite-first-name" name="firstName" onBlur={() => blur("firstName")} onChange={(event) => update("firstName", event.target.value)} placeholder="Ingrese el nombre" value={values.firstName} />{errorFor("firstName") ? <p className="text-sm font-medium text-danger" id="invite-first-name-error">{errorFor("firstName")}</p> : null}</div>
        <div className="space-y-2"><label className="block text-sm font-semibold text-ink" htmlFor="invite-last-name">Apellido <span className="text-danger">*</span></label><input aria-describedby={errorFor("lastName") ? "invite-last-name-error" : undefined} aria-invalid={Boolean(errorFor("lastName"))} className={cn("field-control", errorFor("lastName") && "field-control-invalid")} id="invite-last-name" name="lastName" onBlur={() => blur("lastName")} onChange={(event) => update("lastName", event.target.value)} placeholder="Ingrese el apellido" value={values.lastName} />{errorFor("lastName") ? <p className="text-sm font-medium text-danger" id="invite-last-name-error">{errorFor("lastName")}</p> : null}</div>
        <div className="space-y-2"><label className="block text-sm font-semibold text-ink" htmlFor="invite-email">Correo electrónico <span className="text-danger">*</span></label><input aria-describedby={errorFor("email") ? "invite-email-error" : undefined} aria-invalid={Boolean(errorFor("email"))} autoComplete="email" className={cn("field-control", errorFor("email") && "field-control-invalid")} id="invite-email" name="email" onBlur={() => blur("email")} onChange={(event) => update("email", event.target.value)} placeholder="correo@dominio.com" type="email" value={values.email} />{errorFor("email") ? <p className="text-sm font-medium text-danger" id="invite-email-error">{errorFor("email")}</p> : null}</div>
        <div className="space-y-2"><div className="flex items-center gap-2"><label className="text-sm font-semibold text-ink" htmlFor="invite-role">Rol <span className="text-danger">*</span></label><ContextHelp label="Explicar los roles disponibles" title="¿Qué significa cada rol?"><span className="block"><strong className="text-ink">Propietario</strong><span className="mt-1 block">Administrador de una organización. Gestiona su taller, usuarios, clientes, reparaciones, inventario y configuración según sus permisos.</span></span><span className="mt-4 block"><strong className="text-ink">Cliente</strong><span className="mt-1 block">Cliente final de un taller. Su acceso está limitado a su propio portal, dispositivos, reparaciones, presupuestos y seguimiento habilitado.</span></span></ContextHelp></div><select aria-describedby={errorFor("role") ? "invite-role-error" : undefined} aria-invalid={Boolean(errorFor("role"))} className={cn("field-control", errorFor("role") && "field-control-invalid")} id="invite-role" name="role" onBlur={() => blur("role")} onChange={(event) => update("role", event.target.value)} value={values.role}><option value="">Seleccione el tipo de usuario</option><option value="OWNER">Propietario</option><option value="CUSTOMER">Cliente</option></select>{errorFor("role") ? <p className="text-sm font-medium text-danger" id="invite-role-error">{errorFor("role")}</p> : null}</div>
        <div className="space-y-2 md:col-span-2"><div className="flex items-center gap-2"><label className="text-sm font-semibold text-ink" htmlFor="invite-organization">Organización <span className="text-danger">*</span></label><ContextHelp label="Explicar qué organización seleccionar" title="¿Qué organización debo seleccionar?">Selecciona el taller o espacio de trabajo al que pertenecerá este usuario. Un propietario administrará esa organización; un cliente quedará asociado al taller correspondiente.</ContextHelp></div><select aria-describedby={errorFor("organizationId") ? "invite-organization-error" : undefined} aria-invalid={Boolean(errorFor("organizationId"))} className={cn("field-control", errorFor("organizationId") && "field-control-invalid")} id="invite-organization" name="organizationId" onBlur={() => blur("organizationId")} onChange={(event) => update("organizationId", event.target.value)} value={values.organizationId}><option value="">Seleccione una organización</option>{organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name} · {organization.slug}</option>)}</select>{errorFor("organizationId") ? <p className="text-sm font-medium text-danger" id="invite-organization-error">{errorFor("organizationId")}</p> : null}</div>
      </div>
      <SubmitButton className="w-full sm:w-auto" label="Enviar enlace de activación" pendingLabel="Enviando invitación..." />
    </form>
  );
}
