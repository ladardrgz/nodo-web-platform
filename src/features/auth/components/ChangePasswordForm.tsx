"use client";

import { CheckCircle2 } from "lucide-react";
import { useActionState, useRef, useState, type FormEvent } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button, ButtonLink } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { changePasswordAction } from "@/features/auth/actions";
import { PasswordInput } from "@/features/auth/components/PasswordInput";
import { PasswordRequirements } from "@/features/auth/components/PasswordRequirements";
import { initialAuthActionState, passwordChangeSchema, type AuthFieldErrors } from "@/features/auth/schemas";

type PasswordFlow = "reset" | "configure" | "change";

export function ChangePasswordForm({ flow = "change", successHref = "/login" }: { flow?: PasswordFlow; successHref?: string }) {
  const [state, action, pending] = useActionState(changePasswordAction, initialAuthActionState);
  const [clientErrors, setClientErrors] = useState<AuthFieldErrors>({});
  const [touched, setTouched] = useState<Set<string>>(new Set());
  const [password, setPassword] = useState("");
  const formRef = useRef<HTMLFormElement>(null);
  function validateField(field: "password" | "confirmPassword") {
    const form = formRef.current;
    if (!form) return;
    const result = passwordChangeSchema.safeParse({ password: new FormData(form).get("password"), confirmPassword: new FormData(form).get("confirmPassword") });
    const nextErrors = result.success ? {} : result.error.flatten().fieldErrors;
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: nextErrors[field], ...(field === "password" ? { confirmPassword: nextErrors.confirmPassword } : {}) }));
  }

  function validateBeforeSubmit(event: FormEvent<HTMLFormElement>) {
    const formData = new FormData(event.currentTarget);
    const result = passwordChangeSchema.safeParse({ password: formData.get("password"), confirmPassword: formData.get("confirmPassword") });
    if (result.success) {
      setClientErrors({});
      return;
    }
    event.preventDefault();
    setClientErrors(result.error.flatten().fieldErrors);
  }

  const passwordError = clientErrors.password?.[0] ?? state.fieldErrors?.password?.[0];
  const confirmationError = clientErrors.confirmPassword?.[0] ?? state.fieldErrors?.confirmPassword?.[0];

  if (state.status === "success") {
    const configured = flow === "configure";
    return (
      <div className="public-enter py-2 text-center">
        <ActionStateFeedback state={state} />
        <span className="mx-auto grid size-14 place-items-center rounded-full bg-success-soft text-success"><CheckCircle2 className="size-7" /></span>
        <h2 className="mt-4 text-xl font-bold text-ink">{configured ? "Cuenta configurada" : "Contraseña actualizada"}</h2>
        <p className="mt-2 text-sm leading-6 text-ink-secondary">{configured ? "Tu contraseña se guardó correctamente." : "Tu contraseña se cambió correctamente."}</p>
        <ButtonLink className="mt-6 w-full" href={successHref} size="lg">{successHref === "/login" ? "Iniciar sesión" : "Continuar"}</ButtonLink>
      </div>
    );
  }

  return (
    <form action={action} className="space-y-5" noValidate onSubmit={validateBeforeSubmit} ref={formRef}>
      <input name="flow" type="hidden" value={flow} />
      <ActionStateFeedback state={state} />
      <FormField error={passwordError} hint="Mínimo 12 caracteres, con mayúscula, minúscula, número y símbolo." htmlFor="password" label="Nueva contraseña" required>
        <PasswordInput ariaDescribedBy={passwordError ? "password-error" : undefined} autoComplete="new-password" id="password" invalid={Boolean(passwordError)} name="password" onBlur={() => validateField("password")} onValueChange={(value) => { setPassword(value); if (touched.has("password")) validateField("password"); }} placeholder="Mínimo 12 caracteres" valid={touched.has("password") && !passwordError} />
      </FormField>
      <PasswordRequirements password={password} />
      <FormField error={confirmationError} htmlFor="confirmPassword" label="Repetir contraseña" required>
        <PasswordInput ariaDescribedBy={confirmationError ? "confirmPassword-error" : undefined} autoComplete="new-password" id="confirmPassword" invalid={Boolean(confirmationError)} name="confirmPassword" onBlur={() => validateField("confirmPassword")} onValueChange={() => touched.has("confirmPassword") && validateField("confirmPassword")} placeholder="Repetí tu contraseña" valid={touched.has("confirmPassword") && !confirmationError} />
      </FormField>
      <Button className="w-full" loading={pending} loadingText={flow === "configure" ? "Configurando cuenta…" : "Restableciendo…"} size="lg" type="submit">{flow === "configure" ? "Configurar cuenta" : "Guardar contraseña"}</Button>
    </form>
  );
}
