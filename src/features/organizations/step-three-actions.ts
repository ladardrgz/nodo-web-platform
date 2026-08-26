"use server";

import { revalidatePath } from "next/cache";

import { organizationStepThreeSchema } from "@/features/organizations/schemas";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { GeographyOption } from "@/types/geography";

type LocationField = "countryId" | "provinceId" | "localityId" | "neighborhoodId" | "street" | "streetNumber" | "floor" | "apartment" | "postalCode" | "reference";

export interface OrganizationStepThreeActionState extends ActionFeedbackState {
  completedStep?: 3;
  fieldErrors?: Partial<Record<LocationField, string[]>>;
}

export const initialOrganizationStepThreeState: OrganizationStepThreeActionState = { status: "idle" };

interface OptionsResult {
  options: GeographyOption[];
  error?: string;
}

async function allowGeographyRead() {
  const { organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  return !organization.initial_setup_completed && organization.initial_setup_step >= 3;
}

export async function loadProvincesAction(countryId: string): Promise<OptionsResult> {
  if (!await allowGeographyRead() || !countryId) return { options: [], error: "No pudimos cargar las provincias." };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("provinces").select("id,name").eq("country_id", countryId).eq("is_active", true).order("name");
  if (error) return { options: [], error: "No pudimos cargar las provincias." };
  return { options: (data ?? []) as GeographyOption[] };
}

export async function loadLocalitiesAction(provinceId: string): Promise<OptionsResult> {
  if (!await allowGeographyRead() || !provinceId) return { options: [], error: "No pudimos cargar las localidades." };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("localities").select("id,name").eq("province_id", provinceId).eq("is_active", true).order("name");
  if (error) return { options: [], error: "No pudimos cargar las localidades." };
  return { options: (data ?? []) as GeographyOption[] };
}

export async function loadNeighborhoodsAction(localityId: string): Promise<OptionsResult> {
  if (!await allowGeographyRead() || !localityId) return { options: [], error: "No pudimos cargar los barrios." };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.from("neighborhoods").select("id,name").eq("locality_id", localityId).eq("is_active", true).order("name");
  if (error) return { options: [], error: "No pudimos cargar los barrios." };
  return { options: (data ?? []) as GeographyOption[] };
}

export async function saveOrganizationStepThreeAction(
  _previousState: OrganizationStepThreeActionState,
  formData: FormData,
): Promise<OrganizationStepThreeActionState> {
  const parsed = organizationStepThreeSchema.safeParse({
    countryId: String(formData.get("countryId") ?? ""),
    provinceId: String(formData.get("provinceId") ?? ""),
    localityId: String(formData.get("localityId") ?? ""),
    neighborhoodId: String(formData.get("neighborhoodId") ?? ""),
    street: String(formData.get("street") ?? ""),
    streetNumber: String(formData.get("streetNumber") ?? ""),
    withoutNumber: formData.get("withoutNumber") === "true",
    floor: String(formData.get("floor") ?? ""),
    apartment: String(formData.get("apartment") ?? ""),
    postalCode: String(formData.get("postalCode") ?? ""),
    reference: String(formData.get("reference") ?? ""),
  });
  if (!parsed.success) {
    return {
      status: "error",
      fieldErrors: parsed.error.flatten().fieldErrors,
      feedback: { variant: "error", title: "Completá los campos obligatorios antes de continuar." },
    };
  }

  const { organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  if (organization.initial_setup_completed || organization.initial_setup_step < 3) {
    return { status: "error", feedback: { variant: "error", title: "No pudimos guardar la ubicación. Intentá nuevamente." } };
  }

  const values = parsed.data;
  const supabase = await createSupabaseServerClient();
  const [country, province, locality, neighborhoodCount] = await Promise.all([
    supabase.from("countries").select("id").eq("id", values.countryId).eq("is_active", true).maybeSingle(),
    supabase.from("provinces").select("id").eq("id", values.provinceId).eq("country_id", values.countryId).eq("is_active", true).maybeSingle(),
    supabase.from("localities").select("id").eq("id", values.localityId).eq("province_id", values.provinceId).eq("is_active", true).maybeSingle(),
    supabase.from("neighborhoods").select("id", { count: "exact", head: true }).eq("locality_id", values.localityId).eq("is_active", true),
  ]);

  if (!country.data) return { status: "error", fieldErrors: { countryId: ["Seleccione un país válido."] } };
  if (!province.data) return { status: "error", fieldErrors: { provinceId: ["La provincia seleccionada no corresponde al país."] } };
  if (!locality.data) return { status: "error", fieldErrors: { localityId: ["La localidad seleccionada no corresponde a la provincia."] } };
  if ((neighborhoodCount.count ?? 0) > 0 && !values.neighborhoodId) {
    return { status: "error", fieldErrors: { neighborhoodId: ["Seleccione un barrio."] } };
  }
  if (values.neighborhoodId) {
    const { data: neighborhood } = await supabase.from("neighborhoods").select("id").eq("id", values.neighborhoodId).eq("locality_id", values.localityId).eq("is_active", true).maybeSingle();
    if (!neighborhood) return { status: "error", fieldErrors: { neighborhoodId: ["El barrio seleccionado no corresponde a la localidad."] } };
  }

  const { error } = await supabase.rpc("save_initial_organization_step_three", {
    p_country_id: values.countryId,
    p_province_id: values.provinceId,
    p_locality_id: values.localityId,
    p_neighborhood_id: values.neighborhoodId,
    p_street: values.street,
    p_street_number: values.streetNumber,
    p_without_number: values.withoutNumber,
    p_floor: values.floor,
    p_apartment: values.apartment,
    p_postal_code: values.postalCode,
    p_reference: values.reference,
  });
  if (error) {
    if (process.env.NODE_ENV === "development") console.error("Error técnico al guardar Paso 3:", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos guardar la ubicación. Intentá nuevamente." } };
  }

  revalidatePath("/initial-setup");
  revalidatePath("/dashboard");
  return {
    status: "success",
    completedStep: 3,
    feedback: { variant: "success", title: "Ubicación guardada correctamente." },
  };
}
