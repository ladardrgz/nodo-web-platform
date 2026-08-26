import "server-only";

import { cache } from "react";
import { forbidden, redirect } from "next/navigation";

import { requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AuthContext } from "@/types/auth";
import type { OwnerOrganization } from "@/types/organization";

const ORGANIZATION_COLUMNS = "id,name,trade_name,logo_path,phone,contact_email,address,locality,province,description,status,initial_setup_completed,initial_setup_step";

export interface OwnerOrganizationContext {
  context: AuthContext;
  organization: OwnerOrganization;
}

const readOwnerOrganization = cache(async (): Promise<OwnerOrganizationContext> => {
  const context = await requireRole(["OWNER"]);
  if (!context.profile.organization_id) forbidden();

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("organizations")
    .select(ORGANIZATION_COLUMNS)
    .eq("id", context.profile.organization_id)
    .maybeSingle();

  if (error || !data || data.status !== "ACTIVE") forbidden();
  return { context, organization: data as OwnerOrganization };
});

export async function requireOwnerOrganization(
  options: { allowIncompleteSetup?: boolean } = {},
): Promise<OwnerOrganizationContext> {
  const result = await readOwnerOrganization();
  if (!result.organization.initial_setup_completed && !options.allowIncompleteSetup) {
    redirect("/initial-setup");
  }
  return result;
}
