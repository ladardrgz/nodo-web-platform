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
import { roleCanAccessPath, roleDestination, sanitizeInternalRedirect, withAuthFeedback } from "@/lib/auth/redirects";
import { requireAuth } from "@/lib/auth/session";
import { enforceAuthRateLimit, resetAuthRateLimit } from "@/lib/security/rate-limit";
import { assertPasswordIsNew, rememberPassword } from "@/lib/security/password-history";
import { getAppUrl } from "@/lib/supabase/config";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AuthProfile } from "@/types/auth";

function invalidFields(error: { flatten: () => { fieldErrors: Record<string, string[] | undefined> } }): AuthActionState {
  return { status: "error", message: "Revisá los campos indicados.", fieldErrors: error.flatten().fieldErrors };
}

function configurationFailure(error: unknown): AuthActionState | null {
  if (error instanceof AuthConfigurationError) {
    return { status: "error", message: error.message };
  }
  return null;
}

function logTechnicalAuthError(context: string, error: unknown) {
  if (process.env.NODE_ENV === "development") {
    console.error(`Error técnico de ${context}:`, error);
  }
}

function rateLimitFailure(retryAfterSeconds: number): AuthActionState {
  const minutes = Math.max(1, Math.ceil(retryAfterSeconds / 60));
  return {
    status: "error",
    message: `Demasiados intentos. Volvé a probar en ${minutes} min.`,
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
      return { status: "error", message: "El correo o la contraseña son incorrectos." };
    }

    const profile = await readProfile(data.user.id);
    if (!profile) {
      await supabase.auth.signOut();
      return { status: "error", message: "La cuenta no tiene un perfil habilitado. Contactá al soporte." };
    }
    if (profile.status !== "ACTIVE") {
      await supabase.auth.signOut();
      return { status: "error", message: "La cuenta está suspendida o deshabilitada." };
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
    return { status: "error", message: "No pudimos iniciar sesión. Volvé a intentarlo." };
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
      return { status: "error", message: "No pudimos crear la cuenta. Volvé a intentarlo." };
    }
    if (!data.user) {
      logTechnicalAuthError("registro", new Error("Supabase no devolvió un usuario después de signUp."));
      return { status: "error", message: "No pudimos crear la cuenta. Volvé a intentarlo." };
    }
    if (data.user.identities?.length === 0) {
      return { status: "error", message: "Ya existe una cuenta asociada a este correo." };
    }
    await rememberPassword(data.user.id, parsed.data.password);
    if (data.session) redirect("/portal");
    redirect(`/verify-email?email=${encodeURIComponent(parsed.data.email)}`);
  } catch (error) {
    unstable_rethrow(error);
    logTechnicalAuthError("registro", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", message: "No pudimos crear la cuenta. Volvé a intentarlo." };
  }
}

export async function forgotPasswordAction(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const parsed = forgotPasswordSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return invalidFields(parsed.error);

  try {
    const limit = await enforceAuthRateLimit("PASSWORD_RESET", parsed.data.email);
    if (!limit.allowed) return rateLimitFailure(limit.retryAfterSeconds);

    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
      redirectTo: `${getAppUrl()}/auth/callback?next=/reset-password`,
    });
    if (error) {
      logTechnicalAuthError("recuperación de contraseña", error);
      return { status: "error", message: "No pudimos procesar la solicitud. Intentá más tarde." };
    }

    return {
      status: "success",
      message: "Si existe una cuenta con ese correo, vas a recibir un enlace para restablecerla.",
    };
  } catch (error) {
    logTechnicalAuthError("recuperación de contraseña", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", message: "No pudimos procesar la solicitud. Intentá más tarde." };
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
      return { status: "error", message: "No pudimos reenviar el correo. Intentá más tarde." };
    }

    return { status: "success", message: "Si la cuenta está pendiente, enviamos un nuevo correo." };
  } catch (error) {
    logTechnicalAuthError("reenvío de verificación", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", message: "No pudimos reenviar el correo. Intentá más tarde." };
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

  const context = await requireAuth({ allowPasswordChange: true });
  try {
    const limit = await enforceAuthRateLimit("PASSWORD_RESET", context.userId);
    if (!limit.allowed) return rateLimitFailure(limit.retryAfterSeconds);
    await assertPasswordIsNew(context.userId, parsed.data.password);
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
    if (error) {
      logTechnicalAuthError("cambio de contraseña", error);
      return { status: "error", message: "No pudimos actualizar la contraseña." };
    }
    await rememberPassword(context.userId, parsed.data.password);

    const { error: profileError } = await supabase.rpc("complete_password_change");
    if (profileError) {
      logTechnicalAuthError("finalización de cambio de contraseña", profileError);
      return { status: "error", message: "La contraseña cambió, pero no pudimos completar el perfil. Contactá al soporte." };
    }

    await audit("AUTH_PASSWORD_CHANGED", { mandatory: context.profile.must_change_password });
    redirect(withAuthFeedback("/login", "password_changed"));
  } catch (error) {
    unstable_rethrow(error);
    if (error instanceof Error && error.message === "PASSWORD_REUSED") {
      return { status: "error", message: "No podés reutilizar ninguna de tus últimas 5 contraseñas." };
    }
    logTechnicalAuthError("cambio de contraseña", error);
    const failure = configurationFailure(error);
    if (failure) return failure;
    return { status: "error", message: "No pudimos actualizar la contraseña. Volvé a intentarlo." };
  }
}

export async function logoutAction(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  const { data } = await supabase.auth.getClaims();
  if (data?.claims?.sub) await audit("AUTH_LOGOUT");
  await supabase.auth.signOut();
  redirect(withAuthFeedback("/login", "signed_out"));
}
