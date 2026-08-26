"use server";

import { getOptionalAuthContext } from "@/lib/auth/session";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type IncompleteSetupSection = "ORGANIZATION" | "CONTACT" | "LOCATION";

export interface FinalizeInitialSetupState extends ActionFeedbackState {
  incompleteSection?: IncompleteSetupSection;
}

export const initialFinalizeInitialSetupState: FinalizeInitialSetupState = { status: "idle" };

const incompleteMessages: Record<IncompleteSetupSection, string> = {
  ORGANIZATION: "Falta completar información de Organización.",
  CONTACT: "Falta completar información de Contacto.",
  LOCATION: "Falta completar información de Ubicación.",
};

export async function finalizeInitialSetupAction(
  _previousState: FinalizeInitialSetupState,
  _formData: FormData,
): Promise<FinalizeInitialSetupState> {
  void _previousState;
  void _formData;
  const context = await getOptionalAuthContext();
  if (!context || context.profile.role !== "OWNER" || context.profile.status !== "ACTIVE" || !context.profile.organization_id) {
    return { status: "error", feedback: { variant: "error", title: "No pudimos finalizar la configuración. Intentá nuevamente." } };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("finalize_initial_organization_setup");
  if (error) {
    if (process.env.NODE_ENV === "development") console.error("Error técnico al finalizar onboarding:", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos finalizar la configuración. Intentá nuevamente." } };
  }

  const result = (data as Array<{ status: string; incomplete_section: string | null }> | null)?.[0];
  if (result?.status === "COMPLETED" || result?.status === "ALREADY_COMPLETED") {
    return { status: "success" };
  }
  if (result?.status === "SUSPENDED") {
    return {
      status: "error",
      feedback: { variant: "error", title: "Esta organización está suspendida. Contactá al administrador de Nodo." },
    };
  }
  if (result?.status === "INCOMPLETE" && ["ORGANIZATION", "CONTACT", "LOCATION"].includes(result.incomplete_section ?? "")) {
    const incompleteSection = result.incomplete_section as IncompleteSetupSection;
    return {
      status: "error",
      incompleteSection,
      feedback: { variant: "warning", title: incompleteMessages[incompleteSection] },
    };
  }
  return { status: "error", feedback: { variant: "error", title: "No pudimos finalizar la configuración. Intentá nuevamente." } };
}
