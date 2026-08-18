import { NextResponse, type NextRequest } from "next/server";

import { roleDestination, roleCanAccessPath, sanitizeInternalRedirect } from "@/lib/auth/redirects";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AuthProfile } from "@/types/auth";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const requestedPath = sanitizeInternalRedirect(request.nextUrl.searchParams.get("next"));
  const loginUrl = new URL("/login", request.url);

  if (!code) {
    loginUrl.searchParams.set("error", "missing_code");
    return NextResponse.redirect(loginUrl);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    if (error || !data.user) throw new Error("invalid_callback");

    if (requestedPath === "/reset-password" || requestedPath === "/configure-account") {
      return NextResponse.redirect(new URL(requestedPath, request.url));
    }

    const { data: rawProfile, error: profileError } = await supabase
      .from("profiles")
      .select("id,first_name,last_name,display_name,role,organization_id,must_change_password,status")
      .eq("id", data.user.id)
      .single();
    if (profileError || !rawProfile) throw new Error("missing_profile");

    const profile = rawProfile as AuthProfile;
    if (profile.status !== "ACTIVE") return NextResponse.redirect(new URL("/account-blocked", request.url));

    await supabase.rpc("log_audit_event", {
      p_event_type: "AUTH_CALLBACK_COMPLETED",
      p_entity_type: "AUTH",
      p_entity_id: null,
      p_metadata: { provider: data.user.app_metadata.provider ?? "email" },
    });

    const destination = profile.must_change_password
      ? "/change-password"
      : requestedPath && roleCanAccessPath(profile.role, requestedPath)
        ? requestedPath
        : roleDestination(profile.role);
    const destinationUrl = new URL(destination, request.url);
    destinationUrl.searchParams.set("auth", "session_started");
    return NextResponse.redirect(destinationUrl);
  } catch {
    loginUrl.searchParams.set("error", "callback_failed");
    return NextResponse.redirect(loginUrl);
  }
}
