"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { requireRole } from "@/lib/auth/session";
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

export async function updateProfileAccessAction(formData: FormData) {
  await requireRole(["SUPERADMIN"]);
  const parsed = profileUpdateSchema.safeParse({
    userId: formData.get("userId"),
    role: formData.get("role"),
    status: formData.get("status"),
    organizationId: formData.get("organizationId"),
  });
  if (!parsed.success) redirect("/superadmin?error=invalid_profile");

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("admin_update_profile_access", {
    p_user_id: parsed.data.userId,
    p_role: parsed.data.role,
    p_status: parsed.data.status,
    p_organization_id: parsed.data.organizationId || null,
  });
  if (error) redirect("/superadmin?error=update_failed");
  revalidatePath("/superadmin");
  redirect("/superadmin?message=profile_updated");
}

export async function createOrganizationAction(formData: FormData) {
  await requireRole(["SUPERADMIN"]);
  const parsed = organizationSchema.safeParse({ name: formData.get("name"), slug: formData.get("slug") });
  if (!parsed.success) redirect("/superadmin?error=invalid_organization");

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("admin_create_organization", parsed.data);
  if (error) redirect("/superadmin?error=organization_failed");
  revalidatePath("/superadmin");
  redirect("/superadmin?message=organization_created");
}

export async function inviteUserAction(formData: FormData) {
  const actor = await requireRole(["SUPERADMIN"]);
  const parsed = inviteSchema.safeParse({
    email: formData.get("email"),
    firstName: formData.get("firstName"),
    lastName: formData.get("lastName"),
    role: formData.get("role"),
    organizationId: formData.get("organizationId"),
  });
  if (!parsed.success) redirect("/superadmin?error=invalid_invitation");

  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.auth.admin.inviteUserByEmail(parsed.data.email, {
    redirectTo: `${getAppUrl()}/auth/callback?next=/configure-account`,
    data: { first_name: parsed.data.firstName, last_name: parsed.data.lastName },
  });
  if (error || !data.user) redirect("/superadmin?error=invitation_failed");

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
  if (profileError) redirect("/superadmin?error=invitation_profile_failed");

  const supabase = await createSupabaseServerClient();
  await supabase.rpc("log_audit_event", {
    p_event_type: "ADMIN_ACCOUNT_INVITED",
    p_entity_type: "PROFILE",
    p_entity_id: data.user.id,
    p_metadata: { role: parsed.data.role, actor: actor.userId },
  });
  revalidatePath("/superadmin");
  redirect("/superadmin?message=user_invited");
}
