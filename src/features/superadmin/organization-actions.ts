"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireRole } from "@/lib/auth/session";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import { enforceAuthRateLimit } from "@/lib/security/rate-limit";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const schema = z.object({ organizationId: z.uuid(), status: z.enum(["ACTIVE", "SUSPENDED"]), confirmation: z.string().max(20) });

export async function setOrganizationStatusAction(_state: ActionFeedbackState, formData: FormData): Promise<ActionFeedbackState> {
  const actor = await requireRole(["SUPERADMIN"]);
  const parsed = schema.safeParse({ organizationId: formData.get("organizationId"), status: formData.get("status"), confirmation: formData.get("confirmation") });
  if (!parsed.success || (parsed.data.status === "SUSPENDED" && parsed.data.confirmation !== "SUSPENDER")) return { status: "error", feedback: { variant: "warning", title: "La confirmación no es válida." } };
  try {
    const limit = await enforceAuthRateLimit("ADMIN_MUTATION", actor.userId);
    if (!limit.allowed) return { status: "error", feedback: { variant: "warning", title: "Demasiadas operaciones", description: "Esperá unos minutos antes de volver a intentarlo." } };
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.rpc("admin_set_organization_status", { p_organization_id: parsed.data.organizationId, p_status: parsed.data.status, p_confirmation: parsed.data.confirmation });
    if (error) throw error;
    revalidatePath("/superadmin");
    revalidatePath(`/superadmin/organizations/${parsed.data.organizationId}`);
    return { status: "success", feedback: { variant: "success", title: parsed.data.status === "SUSPENDED" ? "Organización suspendida correctamente." : "Organización reactivada correctamente." } };
  } catch (error) {
    if (process.env.NODE_ENV === "development") console.error("Error técnico al cambiar estado de organización:", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos completar la operación. Intentá nuevamente." } };
  }
}
