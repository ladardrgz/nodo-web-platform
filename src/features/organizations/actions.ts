"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";

import { organizationSettingsInputSchema } from "@/features/organizations/organization-settings-schema";
import type { OrganizationSetupActionState } from "@/features/organizations/action-states";
import { ORGANIZATION_LOGO_EXTENSIONS, validateOrganizationLogoFile } from "@/lib/organizations/logo-validation";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const LOGO_BUCKET = "organization-logos";

export async function saveOrganizationSetupAction(
  _previousState: OrganizationSetupActionState,
  formData: FormData,
): Promise<OrganizationSetupActionState> {
  const parsed = organizationSettingsInputSchema.safeParse({
    name: String(formData.get("name") ?? ""),
    phoneCountry: String(formData.get("phoneCountry") ?? ""),
    phoneNationalNumber: String(formData.get("phoneNationalNumber") ?? ""),
    contactEmail: String(formData.get("contactEmail") ?? ""),
    countryId: String(formData.get("countryId") ?? ""),
    provinceId: String(formData.get("provinceId") ?? ""),
    localityId: String(formData.get("localityId") ?? ""),
    neighborhoodId: String(formData.get("neighborhoodId") ?? ""),
    addressLine: String(formData.get("addressLine") ?? ""),
  });
  if (!parsed.success) return { status: "error", fieldErrors: parsed.error.flatten().fieldErrors };
  if (formData.get("truthfulConfirmation") !== "true") {
    return { status: "error", feedback: { variant: "warning", title: "Confirmá los datos antes de guardar." } };
  }

  const { organization } = await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data: authData } = await supabase.auth.getUser();
  const sameAsPersonalPhone = Boolean(authData.user?.phone) && authData.user?.phone?.trim() === parsed.data.phone.number;
  if (sameAsPersonalPhone && formData.get("personalPhoneConfirmed") !== "true") {
    return {
      status: "error",
      requiresPersonalPhoneConfirmation: true,
      fieldErrors: { phoneNationalNumber: ["Confirmá si querés utilizar tu número personal como contacto del negocio."] },
    };
  }

  const rawLogo = formData.get("logo");
  const logo = rawLogo instanceof File && rawLogo.size > 0 ? rawLogo : null;
  if (logo) {
    const logoError = await validateOrganizationLogoFile(logo);
    if (logoError) return { status: "error", fieldErrors: { logo: [logoError] } };
  }

  const values = parsed.data;
  const [country, province, locality, neighborhoodCount] = await Promise.all([
    supabase.from("countries").select("id").eq("id", values.countryId).eq("is_active", true).maybeSingle(),
    supabase.from("provinces").select("id").eq("id", values.provinceId).eq("country_id", values.countryId).eq("is_active", true).maybeSingle(),
    supabase.from("localities").select("id").eq("id", values.localityId).eq("province_id", values.provinceId).eq("is_active", true).maybeSingle(),
    supabase.from("neighborhoods").select("id", { count: "exact", head: true }).eq("locality_id", values.localityId).eq("is_active", true),
  ]);
  if (!country.data) return { status: "error", fieldErrors: { countryId: ["Seleccioná un país válido."] } };
  if (!province.data) return { status: "error", fieldErrors: { provinceId: ["La provincia o estado no corresponde al país seleccionado."] } };
  if (!locality.data) return { status: "error", fieldErrors: { localityId: ["La localidad no corresponde a la provincia o estado seleccionado."] } };
  if ((neighborhoodCount.count ?? 0) > 0 && !values.neighborhoodId) return { status: "error", fieldErrors: { neighborhoodId: ["Seleccioná un barrio."] } };
  if (values.neighborhoodId) {
    const { data: neighborhood } = await supabase.from("neighborhoods").select("id").eq("id", values.neighborhoodId).eq("locality_id", values.localityId).eq("is_active", true).maybeSingle();
    if (!neighborhood) return { status: "error", fieldErrors: { neighborhoodId: ["El barrio no corresponde a la localidad seleccionada."] } };
  }

  let uploadedLogoPath: string | null = null;
  let nextLogoPath = organization.logo_path;
  try {
    if (logo) {
      const extension = ORGANIZATION_LOGO_EXTENSIONS[logo.type as keyof typeof ORGANIZATION_LOGO_EXTENSIONS];
      uploadedLogoPath = `${organization.id}/logo/${randomUUID()}.${extension}`;
      const { error: uploadError } = await supabase.storage.from(LOGO_BUCKET).upload(uploadedLogoPath, logo, { cacheControl: "3600", contentType: logo.type, upsert: false });
      if (uploadError) {
        await supabase.storage.from(LOGO_BUCKET).remove([uploadedLogoPath]);
        return { status: "error", feedback: { variant: "error", title: "No pudimos cargar el logo. Intentá nuevamente." } };
      }
      nextLogoPath = uploadedLogoPath;
    }

    const { error } = await supabase.rpc("update_owner_organization_settings", {
      p_name: values.name,
      p_logo_path: nextLogoPath,
      p_phone: values.phone.number,
      p_phone_country_code: values.phone.countryCode,
      p_phone_calling_code: values.phone.callingCode,
      p_phone_national_number: values.phone.nationalNumber,
      p_contact_email: values.contactEmail,
      p_country_id: values.countryId,
      p_province_id: values.provinceId,
      p_locality_id: values.localityId,
      p_neighborhood_id: values.neighborhoodId,
      p_street: values.address.street,
      p_street_number: values.address.streetNumber,
      p_without_number: values.address.withoutNumber,
    });
    if (error) throw error;

    if (uploadedLogoPath && organization.logo_path && organization.logo_path !== uploadedLogoPath) {
      const { error: cleanupError } = await supabase.storage.from(LOGO_BUCKET).remove([organization.logo_path]);
      if (cleanupError && process.env.NODE_ENV === "development") console.error("No se pudo limpiar el logo anterior.");
    }
  } catch (error) {
    if (uploadedLogoPath) await supabase.storage.from(LOGO_BUCKET).remove([uploadedLogoPath]);
    if (process.env.NODE_ENV === "development") console.error("Error técnico al actualizar la organización.");
    const conflict = error && typeof error === "object" && "code" in error && error.code === "23505";
    return conflict
      ? { status: "error", fieldErrors: { name: ["Ese nombre ya está siendo utilizado por otra organización."] } }
      : { status: "error", feedback: { variant: "error", title: "No pudimos guardar los datos de la organización. Intentá nuevamente." } };
  }

  revalidatePath("/dashboard");
  revalidatePath("/organization-settings");
  return {
    status: "success",
    feedback: { variant: "success", title: logo ? "Logo y datos de la organización guardados correctamente." : "Datos de la organización guardados correctamente." },
  };
}
