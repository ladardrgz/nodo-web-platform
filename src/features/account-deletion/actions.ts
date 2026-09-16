"use server";

import { revalidatePath } from "next/cache";

import type { DeletionActionState, DeletionBlocker, DeletionSubject } from "@/features/account-deletion/types";
import { requireAuth, requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

function normalizedReason(formData: FormData): string {
  return String(formData.get("reason") ?? "").trim().replace(/\s+/g, " ");
}

export async function requestDeletionAction(
  _previous: DeletionActionState,
  formData: FormData,
): Promise<DeletionActionState> {
  const subject = String(formData.get("subject")) as DeletionSubject;
  const reason = normalizedReason(formData);
  if (!['ORGANIZATION', 'CUSTOMER_ACCOUNT'].includes(subject)) {
    return { status: "error", feedback: { variant: "error", title: "No pudimos procesar la solicitud de baja." } };
  }
  if (reason.length < 3 || reason.length > 300) {
    return { status: "error", feedback: { variant: "warning", title: "Indicá un motivo de entre 3 y 300 caracteres." } };
  }

  await requireRole([subject === "ORGANIZATION" ? "OWNER" : "CUSTOMER"]);
  const supabase = await createSupabaseServerClient();
  const rpcName = subject === "ORGANIZATION" ? "request_organization_deletion" : "request_customer_account_deletion";
  const { data, error } = await supabase.rpc(rpcName, { p_reason: reason });
  if (error) {
    const known = error.message.includes("ORGANIZATION_UNAVAILABLE")
      ? "La organización no está disponible para solicitar la baja."
      : error.message.includes("INVALID_REASON")
        ? "El motivo de la baja no es válido."
        : "No pudimos solicitar la baja. Intentá nuevamente.";
    return { status: "error", feedback: { variant: "error", title: known } };
  }

  const result = data as { ok?: boolean; blockers?: DeletionBlocker[] } | null;
  if (!result?.ok) {
    return {
      status: "error",
      blockers: result?.blockers ?? [],
      feedback: { variant: "warning", title: "Antes de dar de baja la cuenta, resolvé las operaciones pendientes." },
    };
  }

  revalidatePath("/organization-settings");
  revalidatePath("/portal");
  return {
    status: "success",
    completed: true,
    feedback: {
      variant: "success",
      title: subject === "ORGANIZATION" ? "Baja de la organización solicitada correctamente." : "Baja de la cuenta solicitada correctamente.",
      description: "Podés reactivarla durante los próximos 30 días.",
      duration: 6500,
    },
  };
}

export async function cancelDeletionAction(
  _previous: DeletionActionState,
  _formData: FormData,
): Promise<DeletionActionState> {
  void _previous;
  void _formData;
  await requireAuth({ allowPendingDeletion: true });
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("cancel_my_pending_deletion");
  if (error) {
    const title = error.message.includes("RECOVERY_PERIOD_EXPIRED")
      ? "El período de recuperación ya finalizó."
      : "No pudimos reactivar la cuenta. Intentá nuevamente.";
    return { status: "error", feedback: { variant: "error", title } };
  }
  const result = data as { subjectType?: DeletionSubject } | null;
  return {
    status: "success",
    completed: true,
    feedback: {
      variant: "success",
      title: result?.subjectType === "ORGANIZATION" ? "Organización reactivada correctamente." : "Cuenta reactivada correctamente.",
    },
  };
}
