"use client";

import { Mail, UserRound } from "lucide-react";
import { useActionState, useRef, useState, type FormEvent } from "react";

import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { registerAction } from "@/features/auth/actions";
import { AuthStateFeedback } from "@/features/auth/components/AuthStateFeedback";
import { PasswordInput } from "@/features/auth/components/PasswordInput";
import { PasswordRequirements } from "@/features/auth/components/PasswordRequirements";
import { initialAuthActionState, registerSchema, type AuthFieldErrors } from "@/features/auth/schemas";
import { cn } from "@/lib/cn";

export function RegisterForm() {
  const [state, action, pending] = useActionState(registerAction, initialAuthActionState);
  const [clientErrors, setClientErrors] = useState<AuthFieldErrors>({});
  const [touched, setTouched] = useState<Set<string>>(new Set());
  const [password, setPassword] = useState("");
  const formRef = useRef<HTMLFormElement>(null);

  function validateField(field: "firstName" | "lastName" | "email" | "password" | "confirmPassword") {
    const form = formRef.current;
    if (!form) return;
    const result = registerSchema.safeParse({
      firstName: new FormData(form).get("firstName"), lastName: new FormData(form).get("lastName"), email: new FormData(form).get("email"), password: new FormData(form).get("password"), confirmPassword: new FormData(form).get("confirmPassword"),
    });
    const nextErrors = result.success ? {} : result.error.flatten().fieldErrors;
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: nextErrors[field], ...(field === "password" ? { confirmPassword: nextErrors.confirmPassword } : {}) }));
  }

  function validateBeforeSubmit(event: FormEvent<HTMLFormElement>) {
    const formData = new FormData(event.currentTarget);
    const result = registerSchema.safeParse({
      firstName: formData.get("firstName"),
      lastName: formData.get("lastName"),
      email: formData.get("email"),
      password: formData.get("password"),
      confirmPassword: formData.get("confirmPassword"),
    });
    if (result.success) {
      setClientErrors({});
      return;
    }

    event.preventDefault();
    setClientErrors(result.error.flatten().fieldErrors);
  }

  const errorFor = (field: string) => clientErrors[field]?.[0] ?? state.fieldErrors?.[field]?.[0];
  const validFor = (field: string) => touched.has(field) && !errorFor(field);

  return (
    <form action={action} className="space-y-2" noValidate onSubmit={validateBeforeSubmit} ref={formRef}>
      <AuthStateFeedback state={state} />
      <div className="grid gap-2 sm:grid-cols-2">
        {(["firstName", "lastName"] as const).map((id) => {
          const error = errorFor(id);
          return (
            <FormField error={error} htmlFor={id} key={id} label={id === "firstName" ? "Nombre" : "Apellido"} required>
              <div className="input-with-leading-icon relative">
                <UserRound className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-ink-muted" />
                <input aria-describedby={error ? `${id}-error` : undefined} aria-invalid={Boolean(error)} autoComplete={id === "firstName" ? "given-name" : "family-name"} className={cn("field-control", error ? "field-control-invalid" : validFor(id) && "field-control-valid")} id={id} name={id} onBlur={() => validateField(id)} onChange={() => touched.has(id) && validateField(id)} placeholder={id === "firstName" ? "Ej: Lada" : "Ej: Rodriguez"} />
              </div>
            </FormField>
          );
        })}
      </div>
      <FormField error={errorFor("email")} htmlFor="email" label="Correo electrónico" required>
        <div className="input-with-leading-icon relative">
          <Mail className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-ink-muted" />
          <input aria-describedby={errorFor("email") ? "email-error" : undefined} aria-invalid={Boolean(errorFor("email"))} autoComplete="email" className={cn("field-control", errorFor("email") ? "field-control-invalid" : validFor("email") && "field-control-valid")} id="email" name="email" onBlur={() => validateField("email")} onChange={() => touched.has("email") && validateField("email")} placeholder="Ej: usuario@email.com" type="email" />
        </div>
      </FormField>
      <FormField error={errorFor("password")} hint="Mínimo 12 caracteres, con mayúscula, minúscula, número y símbolo." htmlFor="password" label="Contraseña" required>
        <PasswordInput ariaDescribedBy={errorFor("password") ? "password-error" : undefined} autoComplete="new-password" id="password" invalid={Boolean(errorFor("password"))} name="password" onBlur={() => validateField("password")} onValueChange={(value) => { setPassword(value); if (touched.has("password")) validateField("password"); }} placeholder="Mínimo 12 caracteres" valid={validFor("password")} />
      </FormField>
      <PasswordRequirements password={password} />
      <FormField error={errorFor("confirmPassword")} htmlFor="confirmPassword" label="Repetir contraseña" required>
        <PasswordInput ariaDescribedBy={errorFor("confirmPassword") ? "confirmPassword-error" : undefined} autoComplete="new-password" id="confirmPassword" invalid={Boolean(errorFor("confirmPassword"))} name="confirmPassword" onBlur={() => validateField("confirmPassword")} onValueChange={() => touched.has("confirmPassword") && validateField("confirmPassword")} placeholder="Repetí tu contraseña" valid={validFor("confirmPassword")} />
      </FormField>
      <Button className="w-full" disabled={pending} type="submit">{pending ? "Creando cuenta…" : "Crear cuenta"}</Button>
    </form>
  );
}
