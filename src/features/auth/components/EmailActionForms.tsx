"use client";

import { Mail } from "lucide-react";
import { useActionState, useRef, useState, type FormEvent } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { forgotPasswordAction, resendVerificationAction } from "@/features/auth/actions";
import { forgotPasswordSchema, initialAuthActionState } from "@/features/auth/schemas";
import { cn } from "@/lib/cn";

function EmailField({ error, defaultValue, valid, onBlur, onChange }: { error?: string; defaultValue?: string; valid?: boolean; onBlur: () => void; onChange: () => void }) {
  return (
    <FormField error={error} htmlFor="email" label="Correo electrónico" required>
      <div className="input-with-leading-icon relative">
        <Mail className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-ink-muted" />
        <input aria-describedby={error ? "email-error" : undefined} aria-invalid={Boolean(error)} autoComplete="email" className={cn("field-control", error ? "field-control-invalid" : valid && "field-control-valid")} defaultValue={defaultValue} id="email" name="email" onBlur={onBlur} onChange={onChange} placeholder="Ej: usuario@email.com" type="email" />
      </div>
    </FormField>
  );
}

function clientEmailError(event: FormEvent<HTMLFormElement>): string | undefined {
  const result = forgotPasswordSchema.safeParse({ email: new FormData(event.currentTarget).get("email") });
  if (result.success) return undefined;
  event.preventDefault();
  return result.error.flatten().fieldErrors.email?.[0];
}

export function ForgotPasswordForm() {
  const [state, action, pending] = useActionState(forgotPasswordAction, initialAuthActionState);
  const [clientError, setClientError] = useState<string>();
  const [touched, setTouched] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const error = clientError ?? state.fieldErrors?.email?.[0];
  const validateEmail = () => {
    const form = formRef.current;
    if (!form) return;
    const result = forgotPasswordSchema.safeParse({ email: new FormData(form).get("email") });
    setTouched(true);
    setClientError(result.success ? undefined : result.error.flatten().fieldErrors.email?.[0]);
  };
  return (
    <form action={action} className="space-y-5" noValidate onSubmit={(event) => setClientError(clientEmailError(event))} ref={formRef}>
      <ActionStateFeedback state={state} />
      <EmailField error={error} onBlur={validateEmail} onChange={() => touched && validateEmail()} valid={touched && !error} />
      <Button className="w-full" loading={pending} loadingText="Enviando…" size="lg" type="submit">Enviar enlace seguro</Button>
    </form>
  );
}

export function ResendVerificationForm({ email }: { email?: string }) {
  const [state, action, pending] = useActionState(resendVerificationAction, initialAuthActionState);
  const [clientError, setClientError] = useState<string>();
  const [touched, setTouched] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);
  const error = clientError ?? state.fieldErrors?.email?.[0];
  const validateEmail = () => {
    const form = formRef.current;
    if (!form) return;
    const result = forgotPasswordSchema.safeParse({ email: new FormData(form).get("email") });
    setTouched(true);
    setClientError(result.success ? undefined : result.error.flatten().fieldErrors.email?.[0]);
  };
  return (
    <form action={action} className="space-y-5" noValidate onSubmit={(event) => setClientError(clientEmailError(event))} ref={formRef}>
      <ActionStateFeedback state={state} />
      <EmailField defaultValue={email} error={error} onBlur={validateEmail} onChange={() => touched && validateEmail()} valid={touched && !error} />
      <Button className="w-full" loading={pending} loadingText="Reenviando…" type="submit">Reenviar verificación</Button>
    </form>
  );
}
