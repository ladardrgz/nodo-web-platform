"use client";

import { KeyRound, Mail, Pencil, ShieldCheck, X } from "lucide-react";
import { startTransition, useActionState, useState, type FormEvent } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { PasswordInput } from "@/features/auth/components/PasswordInput";
import { PasswordRequirements } from "@/features/auth/components/PasswordRequirements";
import { changeSuperadminPasswordAction, requestSuperadminPasswordResetAction, updateSuperadminProfileAction } from "@/features/superadmin/profile-actions";
import { normalizeProfileValues, superadminPasswordSchema, superadminProfileSchema, type ProfileActionState } from "@/features/superadmin/profile-schema";
import { cn } from "@/lib/cn";

const initialState: ProfileActionState = { status: "idle" };
type PersonalValues = { firstName: string; lastName: string; displayName: string };

function PersonalData({ initialValues, email }: { initialValues: PersonalValues; email: string }) {
  const [editing, setEditing] = useState(false);
  const [saved, setSaved] = useState(initialValues);
  const [values, setValues] = useState(initialValues);
  const [touched, setTouched] = useState<Set<keyof PersonalValues>>(new Set());
  const [submitted, setSubmitted] = useState(false);

  const [state, action, pending] = useActionState(async (previous: ProfileActionState, formData: FormData) => {
    const next = await updateSuperadminProfileAction(previous, formData);
    if (next.status === "success") {
      const normalized = normalizeProfileValues(values);
      setSaved(normalized);
      setValues(normalized);
      setEditing(false);
      setTouched(new Set());
      setSubmitted(false);
    }
    return next;
  }, initialState);

  const errorFor = (field: keyof PersonalValues) => {
    if (!touched.has(field) && !submitted) return state.fieldErrors?.[field]?.[0];
    const result = superadminProfileSchema.shape[field].safeParse(values[field]);
    return result.success ? state.fieldErrors?.[field]?.[0] : result.error.issues[0]?.message;
  };
  const cancel = () => { setValues(saved); setEditing(false); setTouched(new Set()); setSubmitted(false); };
  const submit = (event: FormEvent<HTMLFormElement>) => {
    setSubmitted(true);
    const result = superadminProfileSchema.safeParse(values);
    if (!result.success) event.preventDefault();
  };

  return (
    <section className="rounded-xl border border-line bg-surface-raised p-5 sm:p-6">
      <ActionStateFeedback state={state} />
      <div className="flex flex-wrap items-start justify-between gap-4"><div><h2 className="text-lg font-bold text-ink">Datos personales</h2><p className="mt-1 text-sm text-ink-muted">Información visible asociada a tu perfil global.</p></div>{!editing ? <Button onClick={() => setEditing(true)} size="sm" variant="secondary"><Pencil className="size-4" />Editar perfil</Button> : null}</div>
      {!editing ? <dl className="mt-6 grid gap-5 sm:grid-cols-2"><div><dt className="text-xs font-bold uppercase tracking-wide text-ink-muted">Nombre</dt><dd className="mt-1 font-semibold text-ink">{saved.firstName}</dd></div><div><dt className="text-xs font-bold uppercase tracking-wide text-ink-muted">Apellido</dt><dd className="mt-1 font-semibold text-ink">{saved.lastName}</dd></div><div><dt className="text-xs font-bold uppercase tracking-wide text-ink-muted">Nombre visible</dt><dd className="mt-1 font-semibold text-ink">{saved.displayName}</dd></div><div><dt className="text-xs font-bold uppercase tracking-wide text-ink-muted">Email de acceso</dt><dd className="mt-1 break-all font-semibold text-ink">{email}</dd><p className="mt-1 text-xs text-ink-muted">El email de autenticación no se modifica silenciosamente desde este formulario.</p></div></dl> : <form action={action} className="mt-6 space-y-5" noValidate onSubmit={submit}><div className="grid gap-5 sm:grid-cols-2"><FormField error={errorFor("firstName")} htmlFor="profile-first-name" label="Nombre" required><input aria-invalid={Boolean(errorFor("firstName"))} className={cn("field-control", errorFor("firstName") && "field-control-invalid")} id="profile-first-name" name="firstName" onBlur={() => setTouched((current) => new Set(current).add("firstName"))} onChange={(event) => setValues((current) => ({ ...current, firstName: event.target.value }))} value={values.firstName} /></FormField><FormField error={errorFor("lastName")} htmlFor="profile-last-name" label="Apellido" required><input aria-invalid={Boolean(errorFor("lastName"))} className={cn("field-control", errorFor("lastName") && "field-control-invalid")} id="profile-last-name" name="lastName" onBlur={() => setTouched((current) => new Set(current).add("lastName"))} onChange={(event) => setValues((current) => ({ ...current, lastName: event.target.value }))} value={values.lastName} /></FormField><div className="sm:col-span-2"><FormField error={errorFor("displayName")} htmlFor="profile-display-name" label="Nombre visible" required><input aria-invalid={Boolean(errorFor("displayName"))} className={cn("field-control", errorFor("displayName") && "field-control-invalid")} id="profile-display-name" name="displayName" onBlur={() => setTouched((current) => new Set(current).add("displayName"))} onChange={(event) => setValues((current) => ({ ...current, displayName: event.target.value }))} value={values.displayName} /></FormField></div></div><div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button disabled={pending} onClick={cancel} variant="secondary">Cancelar</Button><Button loading={pending} loadingText="Guardando cambios…" type="submit">Guardar cambios</Button></div></form>}
    </section>
  );
}

function AccountSecurity({ email, lastPasswordUpdate }: { email: string; lastPasswordUpdate: string | null }) {
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [passwordConfirmOpen, setPasswordConfirmOpen] = useState(false);
  const [resetOpen, setResetOpen] = useState(false);
  const [passwords, setPasswords] = useState({ currentPassword: "", password: "", confirmPassword: "" });
  const [passwordErrors, setPasswordErrors] = useState<Record<string, string[] | undefined>>({});
  const [passwordTouched, setPasswordTouched] = useState<Set<keyof typeof passwords>>(new Set());
  const [editedPasswordFields, setEditedPasswordFields] = useState<Set<keyof typeof passwords>>(new Set());

  const [passwordState, passwordAction, passwordPending] = useActionState(async (previous: ProfileActionState, formData: FormData) => {
    const next = await changeSuperadminPasswordAction(previous, formData);
    setEditedPasswordFields(new Set());
    setPasswordConfirmOpen(false);
    if (next.status === "success") {
      setPasswords({ currentPassword: "", password: "", confirmPassword: "" });
      setPasswordErrors({});
      setPasswordTouched(new Set());
      setPasswordOpen(false);
    }
    return next;
  }, initialState);
  const [resetState, resetAction, resetPending] = useActionState(async (previous: ProfileActionState, formData: FormData) => {
    const next = await requestSuperadminPasswordResetAction(previous, formData);
    if (next.status === "success") setResetOpen(false);
    return next;
  }, initialState);

  const validatePassword = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const result = superadminPasswordSchema.safeParse(passwords);
    if (!result.success) {
      setPasswordErrors(result.error.flatten().fieldErrors);
      return;
    }
    setPasswordErrors({});
    setPasswordConfirmOpen(true);
  };
  const updatePassword = (field: keyof typeof passwords, value: string) => {
    const nextValues = { ...passwords, [field]: value };
    setPasswords(nextValues);
    setEditedPasswordFields((current) => new Set(current).add(field));
    if (passwordTouched.has(field)) {
      const result = superadminPasswordSchema.safeParse(nextValues);
      setPasswordErrors(result.success ? {} : result.error.flatten().fieldErrors);
    }
  };
  const touchPassword = (field: keyof typeof passwords) => {
    setPasswordTouched((current) => new Set(current).add(field));
    const result = superadminPasswordSchema.safeParse(passwords);
    setPasswordErrors(result.success ? {} : result.error.flatten().fieldErrors);
  };
  const confirmPasswordChange = () => {
    const formData = new FormData();
    formData.set("currentPassword", passwords.currentPassword);
    formData.set("password", passwords.password);
    formData.set("confirmPassword", passwords.confirmPassword);
    startTransition(() => passwordAction(formData));
  };

  const serverPasswordErrors = passwordState.fieldErrors ?? {};
  const passwordErrorFor = (field: keyof typeof passwords) => passwordErrors[field]?.[0] ?? (!editedPasswordFields.has(field) ? serverPasswordErrors[field]?.[0] : undefined);
  return (
    <section className="rounded-xl border border-line bg-surface-raised p-5 sm:p-6">
      <ActionStateFeedback state={passwordState} /><ActionStateFeedback state={resetState} />
      <div className="flex items-start gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><ShieldCheck className="size-5" /></span><div><h2 className="text-lg font-bold text-ink">Seguridad de la cuenta</h2><p className="mt-1 text-sm text-ink-muted">Protegé el acceso global a Nodo mediante los mecanismos de Supabase Auth.</p></div></div>
      <dl className="mt-6 grid gap-4 rounded-lg bg-surface-soft p-4 text-sm sm:grid-cols-2"><div><dt className="text-ink-muted">Email asociado</dt><dd className="mt-1 break-all font-semibold text-ink">{email}</dd></div><div><dt className="text-ink-muted">Última actualización de contraseña</dt><dd className="mt-1 font-semibold text-ink">{lastPasswordUpdate ?? "Sin un evento auditado todavía"}</dd></div></dl>
      <div className="mt-5 flex flex-wrap gap-3"><Button onClick={() => setPasswordOpen((current) => !current)} variant="secondary"><KeyRound className="size-4" />Cambiar contraseña</Button><Button onClick={() => setResetOpen(true)} variant="ghost"><Mail className="size-4" />Enviar enlace de restablecimiento</Button></div>
      {passwordOpen ? <form className="mt-6 max-w-xl space-y-5 border-t border-line pt-6" noValidate onSubmit={validatePassword}><FormField error={passwordErrorFor("currentPassword")} htmlFor="current-password" label="Contraseña actual" required><PasswordInput autoComplete="current-password" id="current-password" invalid={Boolean(passwordErrorFor("currentPassword"))} name="currentPassword" onBlur={() => touchPassword("currentPassword")} onValueChange={(value) => updatePassword("currentPassword", value)} placeholder="Ingresá tu contraseña actual" /></FormField><FormField error={passwordErrorFor("password")} hint="Mínimo 12 caracteres, con mayúscula, minúscula, número y símbolo." htmlFor="new-password" label="Nueva contraseña" required><PasswordInput autoComplete="new-password" id="new-password" invalid={Boolean(passwordErrorFor("password"))} name="password" onBlur={() => touchPassword("password")} onValueChange={(value) => updatePassword("password", value)} placeholder="Mínimo 12 caracteres" /></FormField><PasswordRequirements password={passwords.password} /><FormField error={passwordErrorFor("confirmPassword")} htmlFor="confirm-new-password" label="Confirmar nueva contraseña" required><PasswordInput autoComplete="new-password" id="confirm-new-password" invalid={Boolean(passwordErrorFor("confirmPassword"))} name="confirmPassword" onBlur={() => touchPassword("confirmPassword")} onValueChange={(value) => updatePassword("confirmPassword", value)} placeholder="Repetí tu contraseña" /></FormField><Button type="submit">Revisar cambio</Button></form> : null}

      {passwordConfirmOpen ? <div className="fixed inset-0 z-[75] flex items-start justify-center bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setPasswordConfirmOpen(false); }}><div aria-modal="true" className="w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold text-ink">Confirmar cambio de contraseña</h3><p className="mt-2 text-sm leading-6 text-ink-secondary">La sesión y tu contraseña actual serán verificadas por Supabase Auth. Nodo nunca almacena la contraseña en el perfil ni en auditoría.</p></div><button aria-label="Cerrar confirmación" className="grid size-8 shrink-0 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft" onClick={() => setPasswordConfirmOpen(false)} type="button"><X className="size-4" /></button></div><div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button disabled={passwordPending} onClick={() => setPasswordConfirmOpen(false)} variant="secondary">Cancelar</Button><Button loading={passwordPending} loadingText="Actualizando contraseña…" onClick={confirmPasswordChange}>Confirmar cambio</Button></div></div></div> : null}
      {resetOpen ? <div className="fixed inset-0 z-[75] flex items-start justify-center bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setResetOpen(false); }}><div aria-modal="true" className="w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold text-ink">Enviar enlace de restablecimiento</h3><p className="mt-2 text-sm leading-6 text-ink-secondary">Te enviaremos un enlace seguro al correo asociado a tu cuenta.</p></div><button aria-label="Cerrar confirmación" className="grid size-8 shrink-0 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft" onClick={() => setResetOpen(false)} type="button"><X className="size-4" /></button></div><form action={resetAction} className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button disabled={resetPending} onClick={() => setResetOpen(false)} variant="secondary">Cancelar</Button><Button loading={resetPending} loadingText="Enviando enlace…" type="submit">Enviar enlace</Button></form></div></div> : null}
    </section>
  );
}

export function SuperadminProfile({ profile, email, lastPasswordUpdate }: { profile: PersonalValues; email: string; lastPasswordUpdate: string | null }) {
  return <div className="space-y-6"><PersonalData email={email} initialValues={profile} /><div><p className="mb-3 text-xs font-bold uppercase tracking-[0.16em] text-accent">Seguridad</p><AccountSecurity email={email} lastPasswordUpdate={lastPasswordUpdate} /></div></div>;
}
