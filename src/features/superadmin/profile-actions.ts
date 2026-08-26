"use server";

import { revalidatePath } from "next/cache";

import { superadminPasswordSchema, superadminProfileSchema, type ProfileActionState } from "@/features/superadmin/profile-schema";
import { requireRole } from "@/lib/auth/session";
import { enforceAuthRateLimit } from "@/lib/security/rate-limit";
import { getAppUrl } from "@/lib/supabase/config";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const errorState = (title: string, description?: string): ProfileActionState => ({ status: "error", feedback: { variant: "error", title, description } });

async function auditProfileEvent(eventType: string, userId: string, metadata: Record<string, string | boolean> = {}) {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("log_audit_event", { p_event_type: eventType, p_entity_type: "PROFILE", p_entity_id: userId, p_metadata: metadata });
  if (error) console.error(`Error técnico de auditoría ${eventType}:`, error);
}

export async function updateSuperadminProfileAction(_state: ProfileActionState, formData: FormData): Promise<ProfileActionState> {
  await requireRole(["SUPERADMIN"]);
  const parsed = superadminProfileSchema.safeParse({ firstName: formData.get("firstName"), lastName: formData.get("lastName"), displayName: formData.get("displayName") });
  if (!parsed.success) return { status: "error", fieldErrors: parsed.error.flatten().fieldErrors };

  try {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.rpc("update_own_superadmin_profile", { p_first_name: parsed.data.firstName, p_last_name: parsed.data.lastName, p_display_name: parsed.data.displayName });
    if (error) throw error;
    revalidatePath("/superadmin/profile");
    revalidatePath("/superadmin");
    return { status: "success", submissionId: crypto.randomUUID(), feedback: { variant: "success", title: "Perfil actualizado correctamente." } };
  } catch (error) {
    console.error("Error técnico al actualizar perfil SUPERADMIN:", error);
    return errorState("No pudimos actualizar tu perfil. Intentá nuevamente.");
  }
}

export async function changeSuperadminPasswordAction(_state: ProfileActionState, formData: FormData): Promise<ProfileActionState> {
  const context = await requireRole(["SUPERADMIN"]);
  const parsed = superadminPasswordSchema.safeParse({ currentPassword: formData.get("currentPassword"), password: formData.get("password"), confirmPassword: formData.get("confirmPassword") });
  if (!parsed.success) return { status: "error", fieldErrors: parsed.error.flatten().fieldErrors };

  try {
    const limit = await enforceAuthRateLimit("PASSWORD_RESET", context.userId);
    if (!limit.allowed) return { status: "error", feedback: { variant: "warning", title: "Demasiados intentos", description: "Esperá unos minutos antes de volver a intentarlo." } };
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.updateUser({ current_password: parsed.data.currentPassword, password: parsed.data.password });
    if (error) {
      if (error.code === "same_password") return { status: "error", fieldErrors: { password: ["La nueva contraseña debe ser diferente de la actual."] }, feedback: { variant: "warning", title: "Elegí una contraseña diferente" } };
      if (error.code === "invalid_credentials") return { status: "error", fieldErrors: { currentPassword: ["La contraseña actual no es correcta."] } };
      if (error.code === "reauthentication_needed") return errorState("Necesitamos verificar nuevamente tu identidad.", "Solicitá el enlace de restablecimiento para continuar de forma segura.");
      throw error;
    }
    await auditProfileEvent("PASSWORD_CHANGED", context.userId);
    revalidatePath("/superadmin/profile");
    return { status: "success", submissionId: crypto.randomUUID(), feedback: { variant: "success", title: "Contraseña actualizada correctamente." } };
  } catch (error) {
    console.error("Error técnico al cambiar contraseña SUPERADMIN:", error);
    return errorState("No pudimos actualizar la contraseña. Intentá nuevamente.");
  }
}

export async function requestSuperadminPasswordResetAction(_state: ProfileActionState, _formData: FormData): Promise<ProfileActionState> {
  void _state;
  void _formData;
  const context = await requireRole(["SUPERADMIN"]);
  if (!context.email) return errorState("No pudimos identificar el correo asociado a tu cuenta.");

  try {
    const limit = await enforceAuthRateLimit("PASSWORD_RESET", context.userId);
    if (!limit.allowed) return { status: "error", feedback: { variant: "warning", title: "Demasiados intentos", description: "Esperá unos minutos antes de solicitar otro enlace." } };
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.resetPasswordForEmail(context.email, { redirectTo: `${getAppUrl()}/auth/confirm` });
    if (error) throw error;
    await auditProfileEvent("PASSWORD_RESET_REQUESTED", context.userId);
    return { status: "success", submissionId: crypto.randomUUID(), feedback: { variant: "success", title: "Te enviamos las instrucciones para restablecer tu contraseña." } };
  } catch (error) {
    console.error("Error técnico al solicitar reset SUPERADMIN:", error);
    return errorState("No pudimos enviar las instrucciones. Intentá nuevamente.");
  }
}
