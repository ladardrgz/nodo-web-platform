"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireRole } from "@/lib/auth/session";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const securityEventSchema = z.enum(["MFA_ENROLL_STARTED", "MFA_ENABLED", "MFA_DISABLED"]);

export async function recordSuperadminSecurityEventAction(eventType: string): Promise<void> {
  const context = await requireRole(["SUPERADMIN"]);
  const parsed = securityEventSchema.safeParse(eventType);
  if (!parsed.success) return;
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("log_audit_event", {
    p_event_type: parsed.data,
    p_entity_type: "PROFILE",
    p_entity_id: context.userId,
    p_metadata: {},
  });
  if (error && process.env.NODE_ENV === "development") console.error("Error técnico de auditoría MFA:", error);
  revalidatePath("/superadmin/profile");
}

export async function revokeOtherSessionsAction(_state: ActionFeedbackState, _formData: FormData): Promise<ActionFeedbackState> {
  void _state;
  void _formData;
  const context = await requireRole(["SUPERADMIN"]);
  try {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.signOut({ scope: "others" });
    if (error) throw error;
    const { error: auditError } = await supabase.rpc("log_audit_event", {
      p_event_type: "OTHER_SESSIONS_REVOKED",
      p_entity_type: "PROFILE",
      p_entity_id: context.userId,
      p_metadata: {},
    });
    if (auditError) throw auditError;
    revalidatePath("/superadmin/profile");
    return { status: "success", feedback: { variant: "success", title: "Las demás sesiones fueron cerradas." } };
  } catch (error) {
    if (process.env.NODE_ENV === "development") console.error("Error técnico al revocar sesiones:", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos cerrar las demás sesiones. Intentá nuevamente." } };
  }
}
