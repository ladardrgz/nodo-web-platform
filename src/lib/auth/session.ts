import "server-only";

import { cookies } from "next/headers";
import { forbidden, redirect } from "next/navigation";

import { AuthConfigurationError } from "@/lib/auth/errors";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AppRole, AuthContext, AuthProfile } from "@/types/auth";

const PROFILE_COLUMNS = "id,first_name,last_name,display_name,role,organization_id,must_change_password,status";

export async function getOptionalAuthContext(): Promise<AuthContext | null> {
  // Mantiene la decisión de acceso en tiempo de solicitud incluso si el build no tiene secretos.
  await cookies();
  try {
    const supabase = await createSupabaseServerClient();
    const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();
    const userId = claimsData?.claims?.sub;

    if (claimsError || typeof userId !== "string") return null;

    const { data, error } = await supabase
      .from("profiles")
      .select(PROFILE_COLUMNS)
      .eq("id", userId)
      .maybeSingle();

    if (error || !data) return null;

    return {
      userId,
      email: typeof claimsData?.claims?.email === "string" ? claimsData.claims.email : null,
      profile: data as AuthProfile,
    };
  } catch (error) {
    if (error instanceof AuthConfigurationError) return null;
    throw error;
  }
}

export async function requireAuth(options: { allowPasswordChange?: boolean } = {}): Promise<AuthContext> {
  const context = await getOptionalAuthContext();
  if (!context) redirect("/login");

  if (context.profile.status !== "ACTIVE") redirect("/account-blocked");
  if (context.profile.must_change_password && !options.allowPasswordChange) {
    redirect("/change-password");
  }

  return context;
}

export async function requireRole(allowedRoles: readonly AppRole[]): Promise<AuthContext> {
  const context = await requireAuth();
  if (!allowedRoles.includes(context.profile.role)) forbidden();
  return context;
}
