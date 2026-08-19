import type { ToastOptions } from "@/lib/feedback/types";

export type AuthOperation = "login" | "register" | "recovery" | "invite" | "password" | "configure";

const fallback: Record<AuthOperation, ToastOptions> = {
  login: { variant: "error", title: "No pudimos iniciar sesión", description: "Intentá nuevamente en unos minutos." },
  register: { variant: "error", title: "No pudimos crear la cuenta", description: "Volvé a intentarlo en unos minutos." },
  recovery: { variant: "error", title: "No pudimos enviar el enlace", description: "Intentá nuevamente en unos minutos." },
  invite: { variant: "error", title: "No pudimos enviar la invitación", description: "Volvé a intentarlo en unos minutos." },
  password: { variant: "error", title: "No pudimos actualizar la contraseña", description: "Intentá nuevamente en unos minutos." },
  configure: { variant: "error", title: "No pudimos configurar la cuenta", description: "Intentá nuevamente en unos minutos." },
};

function technicalMessage(error: unknown): string {
  if (!error || typeof error !== "object" || !("message" in error) || typeof error.message !== "string") return "";
  return error.message.toLocaleLowerCase("en-US");
}

export function mapAuthError(error: unknown, operation: AuthOperation): ToastOptions {
  const message = technicalMessage(error);

  if (message.includes("invalid login credentials")) {
    return { variant: "error", title: "No pudimos iniciar sesión", description: "El correo o la contraseña no son correctos." };
  }
  if (message.includes("email not confirmed")) {
    return { variant: "warning", title: "Confirmá tu correo", description: "Primero tenés que verificar tu dirección de correo electrónico." };
  }
  if (message.includes("already registered") || message.includes("already been registered")) {
    return operation === "invite"
      ? { variant: "warning", title: "Usuario ya registrado", description: "Este usuario ya tiene una cuenta en Nodo." }
      : { variant: "error", title: "Correo ya registrado", description: "Ya existe una cuenta asociada a esta dirección." };
  }
  if (message.includes("already invited") || message.includes("invitation") && message.includes("pending")) {
    return { variant: "warning", title: "Invitación pendiente", description: "Ya existe una invitación pendiente para este correo." };
  }
  if (message.includes("rate limit") || message.includes("too many requests") || message.includes("over_email_send_rate_limit")) {
    return { variant: "warning", title: "Demasiados intentos", description: "Esperá unos minutos antes de volver a intentarlo." };
  }
  if (message.includes("token has expired") || message.includes("otp expired")) {
    return { variant: "error", title: "El enlace venció", description: "Solicitá un nuevo enlace para continuar." };
  }
  if (message.includes("otp not found") || message.includes("invalid token") || message.includes("invalid otp")) {
    return { variant: "error", title: "Enlace inválido", description: "Este enlace no es válido o ya fue utilizado." };
  }
  if (message.includes("password") && (message.includes("weak") || message.includes("strength") || message.includes("characters"))) {
    return { variant: "error", title: "Revisá la contraseña", description: "La contraseña no cumple con los requisitos de seguridad." };
  }
  if (error instanceof TypeError || message.includes("fetch failed") || message.includes("network") || message.includes("failed to fetch")) {
    return { variant: "error", title: "No pudimos conectarnos", description: "Revisá tu conexión e intentá nuevamente." };
  }

  return fallback[operation];
}
