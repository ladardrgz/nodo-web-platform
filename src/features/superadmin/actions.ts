"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { mapAuthError } from "@/lib/auth/messages";
import { requireRole } from "@/lib/auth/session";
import type { ActionFeedbackState } from "@/lib/feedback/types";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { getAppUrl } from "@/lib/supabase/config";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const profileUpdateSchema = z.object({
  userId: z.uuid(),
  role: z.enum(["SUPERADMIN", "OWNER", "CUSTOMER"]),
  status: z.enum(["ACTIVE", "SUSPENDED", "DISABLED"]),
  organizationId: z.union([z.uuid(), z.literal("")]),
});

const organizationSchema = z.object({
  name: z.string().trim().min(2).max(120),
  slug: z.string().trim().toLowerCase().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/).max(80),
});

const inviteSchema = z.object({
  email: z.email().trim().toLowerCase(),
  firstName: z.string().trim().min(2).max(80),
  lastName: z.string().trim().min(2).max(80),
  role: z.enum(["OWNER", "CUSTOMER"]),
  organizationId: z.uuid(),
});

function logTechnicalAdminError(context: string, error: unknown) {
  if (process.env.NODE_ENV === "development") console.error(`Error técnico de ${context}:`, error);
}

export async function updateProfileAccessAction(_state: ActionFeedbackState, formData: FormData): Promise<ActionFeedbackState> {
  await requireRole(["SUPERADMIN"]);
  const parsed = profileUpdateSchema.safeParse({ userId: formData.get("userId"), role: formData.get("role"), status: formData.get("status"), organizationId: formData.get("organizationId") });
  if (!parsed.success) return { status: "error", feedback: { variant: "warning", title: "Revisá los datos", description: "El rol, el estado o la organización no son válidos." } };

  try {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.rpc("admin_update_profile_access", {
      p_user_id: parsed.data.userId,
      p_role: parsed.data.role,
      p_status: parsed.data.status,
      p_organization_id: parsed.data.organizationId || null,
    });
    if (error) throw error;
    revalidatePath("/superadmin");
    return { status: "success", feedback: { variant: "success", title: "Cambios guardados", description: "El acceso del usuario se actualizó correctamente." } };
  } catch (error) {
    logTechnicalAdminError("actualización de acceso", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos guardar los cambios", description: "Volvé a intentarlo en unos minutos." } };
  }
}

export async function createOrganizationAction(_state: ActionFeedbackState, formData: FormData): Promise<ActionFeedbackState> {
  await requireRole(["SUPERADMIN"]);
  const parsed = organizationSchema.safeParse({ name: formData.get("name"), slug: formData.get("slug") });
  if (!parsed.success) return { status: "error", feedback: { variant: "warning", title: "Revisá la organización", description: "Completá un nombre y un slug válidos." } };

  try {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.rpc("admin_create_organization", parsed.data);
    if (error) throw error;
    revalidatePath("/superadmin");
    return { status: "success", feedback: { variant: "success", title: "Organización creada", description: "La organización ya está disponible en Nodo." } };
  } catch (error) {
    logTechnicalAdminError("creación de organización", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos crear la organización", description: "Revisá que el slug no esté en uso e intentá nuevamente." } };
  }
}

export async function inviteUserAction(_state: ActionFeedbackState, formData: FormData): Promise<ActionFeedbackState> {
  const actor = await requireRole(["SUPERADMIN"]);
  const parsed = inviteSchema.safeParse({ email: formData.get("email"), firstName: formData.get("firstName"), lastName: formData.get("lastName"), role: formData.get("role"), organizationId: formData.get("organizationId") });
  if (!parsed.success) return { status: "error", feedback: { variant: "warning", title: "Revisá la invitación", description: "Completá correctamente todos los datos del usuario." } };

  try {
    const admin = createSupabaseAdminClient();
    const { data, error } = await admin.auth.admin.inviteUserByEmail(parsed.data.email, {
      redirectTo: `${getAppUrl()}/auth/callback?next=/configure-account`,
      data: { first_name: parsed.data.firstName, last_name: parsed.data.lastName },
    });
    if (error || !data.user) {
      if (error) logTechnicalAdminError("invitación", error);
      return { status: "error", feedback: mapAuthError(error, "invite") };
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
    await supabase.rpc("log_audit_event", { p_event_type: "ADMIN_ACCOUNT_INVITED", p_entity_type: "PROFILE", p_entity_id: data.user.id, p_metadata: { role: parsed.data.role, actor: actor.userId } });
    revalidatePath("/superadmin");
    return { status: "success", feedback: { variant: "success", title: "Invitación enviada", description: "El correo de invitación fue enviado correctamente." } };
  } catch (error) {
    logTechnicalAdminError("invitación", error);
    return { status: "error", feedback: mapAuthError(error, "invite") };
  }
}
