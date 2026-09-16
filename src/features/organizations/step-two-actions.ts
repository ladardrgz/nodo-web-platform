"use server";

import { revalidatePath } from "next/cache";

import { organizationStepTwoSchema } from "@/features/organizations/schemas";
import type { OrganizationStepTwoActionState } from "@/features/organizations/action-states";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function saveOrganizationStepTwoAction(
  _previousState: OrganizationStepTwoActionState,
  formData: FormData,
): Promise<OrganizationStepTwoActionState> {
  const parsed = organizationStepTwoSchema.safeParse({
    phone: formData.get("phone"),
    contactEmail: formData.get("contactEmail"),
  });
  if (!parsed.success) {
    return {
      status: "error",
      fieldErrors: parsed.error.flatten().fieldErrors,
      feedback: { variant: "error", title: "Completá los campos obligatorios antes de continuar." },
    };
  }

  const { organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  if (organization.initial_setup_completed || organization.initial_setup_step < 2) {
    return {
      status: "error",
      feedback: { variant: "error", title: "No pudimos guardar los datos de contacto. Intentá nuevamente." },
    };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("save_initial_organization_step_two", {
    p_phone: parsed.data.phone,
    p_contact_email: parsed.data.contactEmail,
  });

  if (error) {
    if (process.env.NODE_ENV === "development") console.error("Error técnico al guardar Paso 2:", error);
    return {
      status: "error",
      feedback: { variant: "error", title: "No pudimos guardar los datos de contacto. Intentá nuevamente." },
    };
  }

  revalidatePath("/initial-setup");
  revalidatePath("/dashboard");
  return {
    status: "success",
    completedStep: 2,
    feedback: { variant: "success", title: "Datos de contacto guardados correctamente." },
  };
}
