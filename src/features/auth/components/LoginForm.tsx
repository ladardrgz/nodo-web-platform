"use client";

import { Mail } from "lucide-react";
import Link from "next/link";
import { useActionState, useRef, useState, type FormEvent } from "react";

import { GoogleIcon } from "@/components/icons/GoogleIcon";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { loginAction } from "@/features/auth/actions";
import { initialAuthActionState, loginSchema, type AuthFieldErrors } from "@/features/auth/schemas";
import { AuthStateFeedback } from "@/features/auth/components/AuthStateFeedback";
import { PasswordInput } from "@/features/auth/components/PasswordInput";
import { cn } from "@/lib/cn";

export function LoginForm({
  nextPath,
  configurationMissing,
  googleAuthEnabled = false,
  initialMessage,
}: {
  nextPath?: string;
  configurationMissing?: boolean;
  googleAuthEnabled?: boolean;
  initialMessage?: string;
}) {
  const [state, action, pending] = useActionState(loginAction, initialAuthActionState);
  const [clientErrors, setClientErrors] = useState<AuthFieldErrors>({});
  const [touched, setTouched] = useState<Set<string>>(new Set());
  const formRef = useRef<HTMLFormElement>(null);

  function validateField(field: "email" | "password") {
    const form = formRef.current;
    if (!form) return;
    const result = loginSchema.safeParse({ email: new FormData(form).get("email"), password: new FormData(form).get("password") });
    const nextErrors = result.success ? {} : result.error.flatten().fieldErrors;
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: nextErrors[field] }));
  }

  function validateBeforeSubmit(event: FormEvent<HTMLFormElement>) {
    const formData = new FormData(event.currentTarget);
    const result = loginSchema.safeParse({ email: formData.get("email"), password: formData.get("password") });
    if (result.success) {
      setClientErrors({});
      return;
    }

    event.preventDefault();
    setClientErrors(result.error.flatten().fieldErrors);
  }

  const emailError = clientErrors.email?.[0] ?? state.fieldErrors?.email?.[0];
  const passwordError = clientErrors.password?.[0] ?? state.fieldErrors?.password?.[0];
  const googleHref = `/auth/google${nextPath ? `?next=${encodeURIComponent(nextPath)}` : ""}`;

  return (
    <form action={action} className="space-y-4" noValidate onSubmit={validateBeforeSubmit} ref={formRef}>
      <input name="next" type="hidden" value={nextPath ?? ""} />
      {configurationMissing ? <p className="rounded-lg border border-warning/35 bg-warning-soft px-3 py-2.5 text-xs leading-5 text-warning">Falta configurar Supabase en este entorno. Revisá <code>.env.example</code>.</p> : null}
      {initialMessage ? <p className="rounded-lg border border-danger/35 bg-danger-soft px-3 py-2.5 text-sm text-danger">{initialMessage}</p> : null}
      <AuthStateFeedback state={state} />

      <FormField error={emailError} htmlFor="email" label="Correo electrónico" required>
        <div className="input-with-leading-icon relative">
          <Mail className="pointer-events-none absolute left-3 top-1/2 size-[18px] -translate-y-1/2 text-ink-muted" />
          <input
            aria-describedby={emailError ? "email-error" : undefined}
            aria-invalid={Boolean(emailError)}
            autoComplete="email"
            className={cn("field-control", emailError ? "field-control-invalid" : touched.has("email") && "field-control-valid")}
            id="email"
            name="email"
            onBlur={() => validateField("email")}
            onChange={() => touched.has("email") && validateField("email")}
            placeholder="Ej: usuario@email.com"
            type="email"
          />
        </div>
      </FormField>

      <FormField error={passwordError} htmlFor="password" label="Contraseña" required>
        <PasswordInput
          ariaDescribedBy={passwordError ? "password-error" : undefined}
          autoComplete="current-password"
          id="password"
          invalid={Boolean(passwordError)}
          name="password"
          onValueChange={() => touched.has("password") && validateField("password")}
          onBlur={() => validateField("password")}
          placeholder="Tu contraseña"
          valid={touched.has("password") && !passwordError}
        />
      </FormField>

      <div className="flex justify-end"><Link className="text-sm font-semibold text-accent hover:text-accent-strong" href="/forgot-password">¿Olvidaste tu contraseña?</Link></div>

      <Button className="w-full" disabled={pending || configurationMissing} type="submit">{pending ? "Iniciando sesión..." : "Iniciar sesión"}</Button>

      <div className="flex items-center gap-3 text-xs text-ink-muted"><span className="h-px flex-1 bg-line" /><span>o</span><span className="h-px flex-1 bg-line" /></div>

      {googleAuthEnabled ? (
        <a
          aria-disabled={configurationMissing || pending}
          className={cn("flex min-h-11 w-full items-center justify-center gap-2.5 rounded-lg border border-line-strong bg-surface px-3 text-sm font-semibold text-ink transition-colors hover:bg-surface-soft focus-visible:outline-accent", (configurationMissing || pending) && "pointer-events-none opacity-50")}
          href={googleHref}
        >
          <GoogleIcon className="size-5 shrink-0" />
          Continuar con Google
        </a>
      ) : (
        <button
          aria-label="Continuar con Google, próximamente"
          className="flex min-h-11 w-full cursor-not-allowed items-center justify-center gap-2.5 rounded-lg border border-line bg-surface-soft px-3 text-sm font-semibold text-ink-muted opacity-75"
          disabled
          type="button"
        >
          <GoogleIcon className="size-5 shrink-0 grayscale-[35%]" />
          <span>Continuar con Google <span className="ml-1 text-xs font-medium">· Próximamente</span></span>
        </button>
      )}
    </form>
  );
}
