"use server";

import { redirect, unstable_rethrow } from "next/navigation";

import {
  forgotPasswordSchema,
  loginSchema,
  passwordChangeSchema,
  registerSchema,
  type AuthActionState,
} from "@/features/auth/schemas";
import { AuthConfigurationError } from "@/lib/auth/errors";
import { mapAuthError } from "@/lib/auth/messages";
import { roleCanAccessPath, roleDestination, sanitizeInternalRedirect, withAuthFeedback } from "@/lib/auth/redirects";
import { requireAuth } from "@/lib/auth/session";
import { enforceAuthRateLimit, resetAuthRateLimit } from "@/lib/security/rate-limit";
import { assertPasswordIsNew, rememberPassword } from "@/lib/security/password-history";
import { getAppUrl } from "@/lib/supabase/config";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AuthProfile } from "@/types/auth";

function invalidFields(error: { flatten: () => { fieldErrors: Record<string, string[] | undefined> } }): AuthActionState {
  return { status: "error", fieldErrors: error.flatten().fieldErrors };
}

function configurationFailure(error: unknown): AuthActionState | null {
  if (error instanceof AuthConfigurationError) {
    return { status: "error", feedback: { variant: "error", title: "Autenticación no disponible", description: "La autenticación no está configurada correctamente en este entorno." } };
  }
  return null;
}

function logTechnicalAuthError(context: string, error: unknown) {
  console.error(`Error técnico de ${context}:`, error);
}

function rateLimitFailure(retryAfterSeconds: number): AuthActionState {
  const minutes = Math.max(1, Math.ceil(retryAfterSeconds / 60));
  return {
    status: "error",
    feedback: { variant: "warning", title: "Demasiados intentos", description: `Esperá ${minutes} min antes de volver a intentarlo.` },
    retryAfterSeconds,
  };
}

async function readProfile(userId: string): Promise<AuthProfile | null> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id,first_name,last_name,display_name,role,organization_id,must_change_password,status")
    .eq("id", userId)
    .maybeSingle();
  return error || !data ? null : (data as AuthProfile);
}

async function audit(eventType: string, metadata: Record<string, string | boolean> = {}) {
  const supabase = await createSupabaseServerClient();
  await supabase.rpc("log_audit_event", {
    p_event_type: eventType,
    p_entity_type: "AUTH",
    p_entity_id: null,
    p_metadata: metadata,
  });
}

export async function loginAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = loginSchema.safeParse({ email: formData.get("email"), password: formData.get("password") });
  if (!parsed.success) return invalidFields(parsed.error);

  try {
    const limit = await enforceAuthRateLimit("LOGIN", parsed.data.email);
    if (!limit.allowed) return rateLimitFailure(limit.retryAfterSeconds);

    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.signInWithPassword(parsed.data);

    if (error || !data.user) {
      if (error) logTechnicalAuthError("inicio de sesión", error);
      return { status: "error", feedback: mapAuthError(error, "login") };
    }

    const profile = await readProfile(data.user.id);
    if (!profile) {
      await supabase.auth.signOut();
      return { status: "error", feedback: { variant: "error", title: "Cuenta sin perfil", description: "La cuenta no tiene un perfil habilitado. Contactá al soporte." } };
    }
    if (profile.status !== "ACTIVE") {
      await supabase.auth.signOut();
      return { status: "error", feedback: { variant: "error", title: "Cuenta no disponible", description: "La cuenta está suspendida o deshabilitada." } };
    }

    await resetAuthRateLimit("LOGIN", parsed.data.email).catch(() => undefined);
    await audit("AUTH_LOGIN", { provider: "password" });
    const requestedPath = sanitizeInternalRedirect(String(formData.get("next") ?? ""));
    const destination = profile.must_change_password
      ? "/change-password"
      : requestedPath && roleCanAccessPath(profile.role, requestedPath)
        ? requestedPath
        : roleDestination(profile.role);
    redirect(withAuthFeedback(destination, "session_started"));
  } catch (error) {
    unstable_rethrow(error);
    logTechnicalAuthError("inicio de sesión", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", feedback: mapAuthError(error, "login") };
  }
}

export async function registerAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = registerSchema.safeParse({
    firstName: formData.get("firstName"),
    lastName: formData.get("lastName"),
    email: formData.get("email"),
    password: formData.get("password"),
    confirmPassword: formData.get("confirmPassword"),
  });
  if (!parsed.success) return invalidFields(parsed.error);

  try {
    const limit = await enforceAuthRateLimit("REGISTER", parsed.data.email);
    if (!limit.allowed) return rateLimitFailure(limit.retryAfterSeconds);

    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        emailRedirectTo: `${getAppUrl()}/auth/callback?next=/portal`,
        data: { first_name: parsed.data.firstName, last_name: parsed.data.lastName },
      },
    });

    if (error) {
      logTechnicalAuthError("registro", error);
      return { status: "error", feedback: mapAuthError(error, "register") };
    }
    if (!data.user) {
      logTechnicalAuthError("registro", new Error("Supabase no devolvió un usuario después de signUp."));
      return { status: "error", feedback: mapAuthError(error, "register") };
    }
    if (data.user.identities?.length === 0) {
      return { status: "error", feedback: { variant: "error", title: "Correo ya registrado", description: "Ya existe una cuenta asociada a esta dirección." } };
    }
    await rememberPassword(data.user.id, parsed.data.password);
    if (data.session) redirect(withAuthFeedback("/portal", "account_created"));
    redirect(withAuthFeedback(`/verify-email?email=${encodeURIComponent(parsed.data.email)}`, "account_created"));
  } catch (error) {
    unstable_rethrow(error);
    logTechnicalAuthError("registro", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", feedback: mapAuthError(error, "register") };
  }
}

export async function forgotPasswordAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = forgotPasswordSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return invalidFields(parsed.error);

  try {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
      redirectTo: `${getAppUrl()}/auth/callback?next=/reset-password`,
    });
    if (error) {
      logTechnicalAuthError("recuperación de contraseña", error);
      return { status: "error", feedback: mapAuthError(error, "recovery") };
    }

    return {
      status: "success",
      feedback: { variant: "success", title: "Revisá tu correo", description: "Si existe una cuenta asociada a esa dirección, recibirás un enlace para restablecer tu contraseña." },
    };
  } catch (error) {
    logTechnicalAuthError("recuperación de contraseña", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", feedback: mapAuthError(error, "recovery") };
  }
}

export async function resendVerificationAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = forgotPasswordSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return invalidFields(parsed.error);

  try {
    const limit = await enforceAuthRateLimit("RESEND_VERIFICATION", parsed.data.email);
    if (!limit.allowed) return rateLimitFailure(limit.retryAfterSeconds);

    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.resend({
      type: "signup",
      email: parsed.data.email,
      options: { emailRedirectTo: `${getAppUrl()}/auth/callback?next=/portal` },
    });
    if (error) {
      logTechnicalAuthError("reenvío de verificación", error);
      return { status: "error", feedback: mapAuthError(error, "recovery") };
    }

    return { status: "success", feedback: { variant: "success", title: "Correo enviado", description: "Si la cuenta está pendiente, enviamos un nuevo enlace de verificación." } };
  } catch (error) {
    logTechnicalAuthError("reenvío de verificación", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", feedback: mapAuthError(error, "recovery") };
  }
}

export async function changePasswordAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = passwordChangeSchema.safeParse({
    password: formData.get("password"),
    confirmPassword: formData.get("confirmPassword"),
  });
  if (!parsed.success) return invalidFields(parsed.error);

  const flow = String(formData.get("flow") ?? "change");

  const context = await requireAuth({ allowPasswordChange: true });
  try {
    const limit = await enforceAuthRateLimit("PASSWORD_RESET", context.userId);
    if (!limit.allowed) return rateLimitFailure(limit.retryAfterSeconds);
    await assertPasswordIsNew(context.userId, parsed.data.password);
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
    if (error) {
      logTechnicalAuthError("cambio de contraseña", error);
      return { status: "error", feedback: mapAuthError(error, flow === "configure" ? "configure" : "password") };
    }
    await rememberPassword(context.userId, parsed.data.password);

    const { error: profileError } = await supabase.rpc("complete_password_change");
    if (profileError) {
      logTechnicalAuthError("finalización de cambio de contraseña", profileError);
      return { status: "error", feedback: { variant: "error", title: "Cambio incompleto", description: "La contraseña cambió, pero no pudimos completar el perfil. Contactá al soporte." } };
    }

    await audit("AUTH_PASSWORD_CHANGED", { mandatory: context.profile.must_change_password });
    if (flow === "reset" || flow === "configure") await supabase.auth.signOut();
    const feedback = flow === "configure"
      ? { variant: "success" as const, title: "Cuenta configurada", description: "Tu contraseña se guardó correctamente. Ya podés iniciar sesión." }
      : { variant: "success" as const, title: "Contraseña actualizada", description: flow === "reset" ? "Tu contraseña se cambió correctamente. Ya podés iniciar sesión." : "Tu contraseña se cambió correctamente." };
    return { status: "success", feedback };
  } catch (error) {
    unstable_rethrow(error);
    if (error instanceof Error && error.message === "PASSWORD_REUSED") {
      return { status: "error", feedback: { variant: "warning", title: flow === "change" ? "Elegí una contraseña diferente" : "Elegí otra contraseña", description: "No podés reutilizar una de tus últimas 5 contraseñas." } };
    }
    logTechnicalAuthError("cambio de contraseña", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", feedback: mapAuthError(error, flow === "configure" ? "configure" : "password") };
  }
}

export async function logoutAction(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.auth.getClaims();
  if (data?.claims?.sub) await audit("AUTH_LOGOUT");
  await supabase.auth.signOut();
  redirect(withAuthFeedback("/login", "signed_out"));
}
