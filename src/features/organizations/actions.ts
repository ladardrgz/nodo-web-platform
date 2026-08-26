"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { organizationSetupSchema } from "@/features/organizations/schemas";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { ActionFeedbackState } from "@/lib/feedback/types";

const LOGO_BUCKET = "organization-logos";
const MAX_LOGO_SIZE = 2 * 1024 * 1024;
const LOGO_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

export interface OrganizationSetupActionState extends ActionFeedbackState {
  fieldErrors?: Record<string, string[] | undefined>;
}

export const initialOrganizationSetupState: OrganizationSetupActionState = { status: "idle" };

export async function saveOrganizationSetupAction(
  _previousState: OrganizationSetupActionState,
  formData: FormData,
): Promise<OrganizationSetupActionState> {
  const parsed = organizationSetupSchema.safeParse({
    name: formData.get("name"),
    tradeName: formData.get("tradeName"),
    phone: formData.get("phone"),
    contactEmail: formData.get("contactEmail"),
    address: formData.get("address"),
    locality: formData.get("locality"),
    province: formData.get("province"),
    description: formData.get("description"),
  });
  if (!parsed.success) {
    return { status: "error", fieldErrors: parsed.error.flatten().fieldErrors };
  }

  const { organization } = await requireOwnerOrganization();
  const rawLogo = formData.get("logo");
  const logo = rawLogo instanceof File && rawLogo.size > 0 ? rawLogo : null;
  if (logo && (!LOGO_EXTENSIONS[logo.type] || logo.size > MAX_LOGO_SIZE)) {
    return {
      status: "error",
      fieldErrors: { logo: [logo.size > MAX_LOGO_SIZE ? "El logo no puede superar los 2 MB." : "Usá un archivo JPG, PNG o WebP."] },
    };
  }

  const supabase = await createSupabaseServerClient();
  let nextLogoPath = organization.logo_path;
  let uploadedLogoPath: string | null = null;

  try {
    if (logo) {
      uploadedLogoPath = `${organization.id}/${randomUUID()}.${LOGO_EXTENSIONS[logo.type]}`;
      const { error: uploadError } = await supabase.storage
        .from(LOGO_BUCKET)
        .upload(uploadedLogoPath, logo, { cacheControl: "3600", contentType: logo.type, upsert: false });
      if (uploadError) throw uploadError;
      nextLogoPath = uploadedLogoPath;
    }

    const { error } = await supabase.rpc("complete_initial_organization_setup", {
      p_name: parsed.data.name,
      p_trade_name: parsed.data.tradeName,
      p_logo_path: nextLogoPath,
      p_phone: parsed.data.phone,
      p_contact_email: parsed.data.contactEmail,
      p_address: parsed.data.address,
      p_locality: parsed.data.locality,
      p_province: parsed.data.province,
      p_description: parsed.data.description,
    });
    if (error) throw error;

    if (uploadedLogoPath && organization.logo_path && organization.logo_path !== uploadedLogoPath) {
      await supabase.storage.from(LOGO_BUCKET).remove([organization.logo_path]);
    }
  } catch (error) {
    if (uploadedLogoPath) await supabase.storage.from(LOGO_BUCKET).remove([uploadedLogoPath]);
    console.error("Error técnico de configuración inicial:", error);
    return {
      status: "error",
      feedback: {
        variant: "error",
        title: "No pudimos guardar la configuración",
        description: "Revisá los datos e intentá nuevamente.",
      },
    };
  }

  revalidatePath("/dashboard");
  revalidatePath("/organization-settings");
  redirect("/dashboard?setup=organization_setup_completed");
}
