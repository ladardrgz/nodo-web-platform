"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { mapAuthError } from "@/lib/auth/messages";
import { requireRole } from "@/lib/auth/session";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import {
  createOrganizationSchema,
  normalizeOrganizationNameForComparison,
  type OrganizationCreationState,
} from "@/features/superadmin/organization-schema";
import { inviteUserSchema, requiredRoleConfirmation, type InvitationState } from "@/features/superadmin/user-schema";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { enforceAuthRateLimit } from "@/lib/security/rate-limit";
import { getAppUrl } from "@/lib/supabase/config";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const profileUpdateSchema = z.object({
  userId: z.uuid(),
  role: z.enum(["SUPERADMIN", "OWNER", "CUSTOMER", "TECHNICIAN"]),
  status: z.enum(["ACTIVE", "SUSPENDED", "DISABLED"]),
  organizationId: z.union([z.uuid(), z.literal("")]),
  confirmation: z.string().max(40),
});

function logTechnicalAdminError(context: string, error: unknown) {
  if (process.env.NODE_ENV === "development") console.error(`Error técnico de ${context}:`, error);
}

export async function updateProfileAccessAction(_state: ActionFeedbackState, formData: FormData): Promise<ActionFeedbackState> {
  const actor = await requireRole(["SUPERADMIN"]);
  const parsed = profileUpdateSchema.safeParse({ userId: formData.get("userId"), role: formData.get("role"), status: formData.get("status"), organizationId: formData.get("organizationId"), confirmation: formData.get("confirmation") });
  if (!parsed.success) return { status: "error", feedback: { variant: "warning", title: "Revisá los datos", description: "El rol, el estado o la organización no son válidos." } };

  try {
    const limit = await enforceAuthRateLimit("ADMIN_MUTATION", actor.userId);
    if (!limit.allowed) return { status: "error", feedback: { variant: "warning", title: "Demasiadas operaciones", description: "Esperá unos minutos antes de volver a intentarlo." } };
    const supabase = await createSupabaseServerClient();
    const { data: currentProfile, error: profileError } = await supabase.from("profiles").select("role,status,organization_id").eq("id", parsed.data.userId).maybeSingle();
    if (profileError || !currentProfile) throw profileError ?? new Error("Profile not found");

    const reducesOwnGlobalAccess = actor.userId === parsed.data.userId && currentProfile.role === "SUPERADMIN" && (parsed.data.role !== "SUPERADMIN" || parsed.data.status !== "ACTIVE");
    const requiredConfirmation = reducesOwnGlobalAccess ? "MI CUENTA" : requiredRoleConfirmation(currentProfile.role, parsed.data.role);
    if (requiredConfirmation && parsed.data.confirmation !== requiredConfirmation) return { status: "error", feedback: { variant: "error", title: "Confirmación incorrecta", description: `Escribí ${requiredConfirmation} exactamente para autorizar este cambio.` } };

    if (parsed.data.role !== "SUPERADMIN") {
      if (!parsed.data.organizationId) return { status: "error", feedback: { variant: "warning", title: "Organización obligatoria", description: "Seleccioná una organización válida para este usuario." } };
      const { data: organization, error: organizationError } = await supabase.from("organizations").select("id").eq("id", parsed.data.organizationId).maybeSingle();
      if (organizationError || !organization) return { status: "error", feedback: { variant: "warning", title: "Organización no válida", description: "La organización seleccionada ya no está disponible." } };
    }

    const { error } = await supabase.rpc("admin_update_profile_access", {
      p_user_id: parsed.data.userId,
      p_role: parsed.data.role,
      p_status: parsed.data.status,
      p_organization_id: parsed.data.organizationId || null,
    });
    if (error) throw error;
    revalidatePath("/superadmin");
    return { status: "success", feedback: { variant: "success", title: "Permisos actualizados correctamente." } };
  } catch (error) {
    if (error instanceof Error && error.message.includes("LAST_ACTIVE_SUPERADMIN")) return { status: "error", feedback: { variant: "warning", title: "Nodo debe conservar al menos un SUPERADMIN activo." } };
    logTechnicalAdminError("actualización de acceso", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos actualizar los permisos. Intentá nuevamente." } };
  }
}

export async function createOrganizationAction(_state: OrganizationCreationState, formData: FormData): Promise<OrganizationCreationState> {
  const actor = await requireRole(["SUPERADMIN"]);
  const parsed = createOrganizationSchema.safeParse({ name: formData.get("name"), slug: formData.get("slug") });
  if (!parsed.success) {
    const fieldErrors = parsed.error.flatten().fieldErrors;
    const hasRequiredFieldsMissing = !String(formData.get("name") ?? "").trim() || !String(formData.get("slug") ?? "").trim();
    return {
      status: "error",
      fieldErrors,
      feedback: hasRequiredFieldsMissing ? { variant: "warning", title: "Completá los campos obligatorios antes de continuar." } : undefined,
    };
  }

  try {
    const limit = await enforceAuthRateLimit("ADMIN_MUTATION", actor.userId);
    if (!limit.allowed) return { status: "error", feedback: { variant: "warning", title: "Demasiadas operaciones", description: "Esperá unos minutos antes de volver a intentarlo." } };
    const supabase = await createSupabaseServerClient();
    const { data: existing, error: lookupError } = await supabase.from("organizations").select("name,slug");
    if (lookupError) throw lookupError;

    const duplicateName = existing?.some((organization) => normalizeOrganizationNameForComparison(organization.name) === normalizeOrganizationNameForComparison(parsed.data.name));
    const duplicateSlug = existing?.some((organization) => organization.slug.toLowerCase() === parsed.data.slug);
    if (duplicateName || duplicateSlug) {
      return {
        status: "error",
        fieldErrors: {
          name: duplicateName ? ["Este nombre ya está siendo utilizado por otra organización."] : undefined,
          slug: duplicateSlug ? ["Este identificador ya está ocupado."] : undefined,
        },
      };
    }

    const { error } = await supabase.rpc("admin_create_organization", parsed.data);
    if (error) {
      if (error.code === "23505") {
        const nameConflict = error.message.includes("organizations_name_normalized_key");
        const slugConflict = error.message.includes("organizations_slug_key");
        return {
          status: "error",
          fieldErrors: {
            name: nameConflict ? ["Este nombre ya está siendo utilizado por otra organización."] : undefined,
            slug: slugConflict ? ["Este identificador ya está ocupado."] : undefined,
          },
          feedback: !nameConflict && !slugConflict ? { variant: "error", title: "No pudimos crear la organización porque ya existe una con esos datos." } : undefined,
        };
      }
      throw error;
    }
    revalidatePath("/superadmin");
    return { status: "success", submissionId: crypto.randomUUID(), feedback: { variant: "success", title: "Organización creada correctamente." } };
  } catch (error) {
    logTechnicalAdminError("creación de organización", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos crear la organización. Intentá nuevamente." } };
  }
}

export async function inviteUserAction(_state: InvitationState, formData: FormData): Promise<InvitationState> {
  const actor = await requireRole(["SUPERADMIN"]);
  const parsed = inviteUserSchema.safeParse({ email: formData.get("email"), firstName: formData.get("firstName"), lastName: formData.get("lastName"), role: formData.get("role"), organizationId: formData.get("organizationId") });
  if (!parsed.success) {
    const hasMissingFields = ["email", "firstName", "lastName", "role", "organizationId"].some((field) => !String(formData.get(field) ?? "").trim());
    return { status: "error", fieldErrors: parsed.error.flatten().fieldErrors, feedback: hasMissingFields ? { variant: "warning", title: "Completá los campos obligatorios antes de continuar." } : undefined };
  }

  try {
    const limit = await enforceAuthRateLimit("ADMIN_MUTATION", actor.userId);
    if (!limit.allowed) return { status: "error", feedback: { variant: "warning", title: "Demasiadas operaciones", description: "Esperá unos minutos antes de volver a intentarlo." } };
    const admin = createSupabaseAdminClient();
    const { data: organization, error: organizationError } = await admin.from("organizations").select("id").eq("id", parsed.data.organizationId).maybeSingle();
    if (organizationError || !organization) return { status: "error", fieldErrors: { organizationId: ["Seleccione la organización a la que pertenecerá."] } };

    let authPage = 1;
    let emailExists = false;
    while (!emailExists) {
      const { data: authUsers, error: usersError } = await admin.auth.admin.listUsers({ page: authPage, perPage: 1000 });
      if (usersError) throw usersError;
      emailExists = authUsers.users.some((user) => user.email?.toLowerCase() === parsed.data.email);
      if (emailExists || authUsers.users.length < 1000) break;
      authPage += 1;
    }
    if (emailExists) {
      return { status: "error", fieldErrors: { email: ["Este correo ya tiene una cuenta o una invitación pendiente."] }, feedback: { variant: "warning", title: "Este correo ya tiene una cuenta o una invitación pendiente." } };
    }

    const { data, error } = await admin.auth.admin.inviteUserByEmail(parsed.data.email, {
      redirectTo: `${getAppUrl()}/auth/callback?next=/configure-account`,
      data: { first_name: parsed.data.firstName, last_name: parsed.data.lastName },
    });
    if (error || !data.user) {
      if (error) logTechnicalAdminError("invitación", error);
      const mapped = mapAuthError(error, "invite");
      if (mapped.title === "Invitación pendiente" || mapped.title === "Correo ya registrado") return { status: "error", fieldErrors: { email: ["Este correo ya tiene una cuenta o una invitación pendiente."] }, feedback: { variant: "warning", title: "Este correo ya tiene una cuenta o una invitación pendiente." } };
      return { status: "error", feedback: { variant: "error", title: "No pudimos enviar la invitación. Intentá nuevamente." } };
    }

    const { error: profileError } = await admin.from("profiles").upsert({
      id: data.user.id,
      first_name: parsed.data.firstName,
      last_name: parsed.data.lastName,
      display_name: `${parsed.data.firstName} ${parsed.data.lastName}`,
      role: parsed.data.role,
      status: "ACTIVE",
      organization_id: parsed.data.organizationId,
      must_change_password: true,
    });
    if (profileError) {
      logTechnicalAdminError("perfil de invitación", profileError);
      return { status: "error", feedback: { variant: "error", title: "Invitación incompleta", description: "El correo se envió, pero el perfil necesita revisión." } };
    }

    const supabase = await createSupabaseServerClient();
    await supabase.rpc("admin_log_organization_event", { p_organization_id: parsed.data.organizationId, p_event_type: "USER_INVITED", p_entity_type: "PROFILE", p_entity_id: data.user.id, p_metadata: { role: parsed.data.role } });
    revalidatePath("/superadmin");
    return { status: "success", submissionId: crypto.randomUUID(), feedback: { variant: "success", title: "Invitación enviada correctamente." } };
  } catch (error) {
    logTechnicalAdminError("invitación", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos enviar la invitación. Intentá nuevamente." } };
  }
}
