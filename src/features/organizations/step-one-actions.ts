"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";

import {
  organizationStepOneSchema,
  validateOrganizationLogo,
} from "@/features/organizations/schemas";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import { ORGANIZATION_LOGO_BUCKET } from "@/lib/organizations/logo";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const LOGO_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

export interface OrganizationStepOneActionState extends ActionFeedbackState {
  completedStep?: 1;
  fieldErrors?: Partial<Record<"legalName" | "commercialName" | "logo", string[]>>;
}

export const initialOrganizationStepOneState: OrganizationStepOneActionState = { status: "idle" };

export async function saveOrganizationStepOneAction(
  _previousState: OrganizationStepOneActionState,
  formData: FormData,
): Promise<OrganizationStepOneActionState> {
  const parsed = organizationStepOneSchema.safeParse({
    legalName: formData.get("legalName"),
    commercialName: formData.get("commercialName"),
  });
  if (!parsed.success) {
    return {
      status: "error",
      fieldErrors: parsed.error.flatten().fieldErrors,
      feedback: { variant: "error", title: "Completá los campos obligatorios antes de continuar." },
    };
  }

  const rawLogo = formData.get("logo");
  const logo = rawLogo instanceof File && rawLogo.size > 0 ? rawLogo : null;
  const logoError = validateOrganizationLogo(logo);
  if (logoError) {
    return { status: "error", fieldErrors: { logo: [logoError] } };
  }

  const { organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  if (organization.initial_setup_completed) {
    return {
      status: "error",
      feedback: { variant: "error", title: "Esta organización ya completó su configuración inicial." },
    };
  }

  const supabase = await createSupabaseServerClient();
  let uploadedLogoPath: string | null = null;
  let nextLogoPath = organization.logo_path;

  if (logo) {
    uploadedLogoPath = `${organization.id}/logo/${randomUUID()}.${LOGO_EXTENSIONS[logo.type]}`;
    const { error: uploadError } = await supabase.storage
      .from(ORGANIZATION_LOGO_BUCKET)
      .upload(uploadedLogoPath, logo, {
        cacheControl: "3600",
        contentType: logo.type,
        upsert: false,
      });

    if (uploadError) {
      if (process.env.NODE_ENV === "development") console.error("Error técnico al subir logo:", uploadError);
      return {
        status: "error",
        feedback: { variant: "error", title: "No pudimos subir el logo. Revisá el archivo e intentá nuevamente." },
      };
    }
    nextLogoPath = uploadedLogoPath;
  }

  const { error } = await supabase.rpc("save_initial_organization_step_one", {
    p_legal_name: parsed.data.legalName,
    p_commercial_name: parsed.data.commercialName,
    p_logo_path: nextLogoPath,
  });

  if (error) {
    if (uploadedLogoPath) await supabase.storage.from(ORGANIZATION_LOGO_BUCKET).remove([uploadedLogoPath]);
    if (process.env.NODE_ENV === "development") console.error("Error técnico al guardar Paso 1:", error);
    if (error.code === "23505") {
      return {
        status: "error",
        fieldErrors: { legalName: ["Ya existe una organización registrada con esta razón social."] },
      };
    }
    return {
      status: "error",
      feedback: { variant: "error", title: "No pudimos guardar los datos de la organización. Intentá nuevamente." },
    };
  }

  if (uploadedLogoPath && organization.logo_path && organization.logo_path !== uploadedLogoPath) {
    const { error: cleanupError } = await supabase.storage
      .from(ORGANIZATION_LOGO_BUCKET)
      .remove([organization.logo_path]);
    if (cleanupError && process.env.NODE_ENV === "development") {
      console.error("No se pudo limpiar el logo anterior:", cleanupError);
    }
  }

  revalidatePath("/initial-setup");
  revalidatePath("/dashboard");
  return {
    status: "success",
    completedStep: 1,
    feedback: { variant: "success", title: "Datos de la organización guardados correctamente." },
  };
}
