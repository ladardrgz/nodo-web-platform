"use client";

import { useActionState, useRef, useState, type FormEvent } from "react";

import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { changePasswordAction } from "@/features/auth/actions";
import { AuthStateFeedback } from "@/features/auth/components/AuthStateFeedback";
import { PasswordInput } from "@/features/auth/components/PasswordInput";
import { PasswordRequirements } from "@/features/auth/components/PasswordRequirements";
import { initialAuthActionState, passwordChangeSchema, type AuthFieldErrors } from "@/features/auth/schemas";

export function ChangePasswordForm() {
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

  return (
    <form action={action} className="space-y-5" noValidate onSubmit={validateBeforeSubmit} ref={formRef}>
      <AuthStateFeedback state={state} />
      <FormField error={passwordError} hint="Mínimo 12 caracteres, con mayúscula, minúscula, número y símbolo." htmlFor="password" label="Nueva contraseña" required>
        <PasswordInput ariaDescribedBy={passwordError ? "password-error" : undefined} autoComplete="new-password" id="password" invalid={Boolean(passwordError)} name="password" onBlur={() => validateField("password")} onValueChange={(value) => { setPassword(value); if (touched.has("password")) validateField("password"); }} placeholder="Mínimo 12 caracteres" valid={touched.has("password") && !passwordError} />
      </FormField>
      <PasswordRequirements password={password} />
      <FormField error={confirmationError} htmlFor="confirmPassword" label="Repetir contraseña" required>
        <PasswordInput ariaDescribedBy={confirmationError ? "confirmPassword-error" : undefined} autoComplete="new-password" id="confirmPassword" invalid={Boolean(confirmationError)} name="confirmPassword" onBlur={() => validateField("confirmPassword")} onValueChange={() => touched.has("confirmPassword") && validateField("confirmPassword")} placeholder="Repetí tu contraseña" valid={touched.has("confirmPassword") && !confirmationError} />
      </FormField>
      <Button className="w-full" disabled={pending} size="lg" type="submit">{pending ? "Actualizando…" : "Guardar contraseña"}</Button>
    </form>
  );
}
