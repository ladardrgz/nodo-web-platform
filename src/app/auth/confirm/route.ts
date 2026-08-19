import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";

import { roleDestination } from "@/lib/auth/redirects";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { AuthProfile } from "@/types/auth";

const allowedTypes = new Set<EmailOtpType>(["email", "signup", "invite", "recovery", "email_change"]);

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const rawType = request.nextUrl.searchParams.get("type") as EmailOtpType | null;
  const loginUrl = new URL("/login", request.url);

  if (!code && (!tokenHash || !rawType || !allowedTypes.has(rawType))) {
    loginUrl.searchParams.set("error", "invalid_confirmation");
    return NextResponse.redirect(loginUrl);
  }

  try {
    const supabase = await createSupabaseServerClient();
    if (code) {
      const { data, error } = await supabase.auth.exchangeCodeForSession(code);
      if (error || !data.user) {
        console.error("Error técnico de confirmación de recovery:", error);
        const errorMessage = error?.message.toLocaleLowerCase("en-US") ?? "";
        loginUrl.searchParams.set("error", errorMessage.includes("expired") ? "recovery_link_expired" : "recovery_link_invalid");
        throw new Error("invalid_recovery_code");
      }

      return NextResponse.redirect(new URL("/reset-password", request.url));
    }

    if (!tokenHash || !rawType || !allowedTypes.has(rawType)) {
      loginUrl.searchParams.set("error", "invalid_confirmation");
      return NextResponse.redirect(loginUrl);
    }

    const { data, error } = await supabase.auth.verifyOtp({ type: rawType, token_hash: tokenHash });
    if (error || !data.user) {
      const errorMessage = error?.message.toLocaleLowerCase("en-US") ?? "";
      if (rawType === "recovery") loginUrl.searchParams.set("error", errorMessage.includes("expired") ? "recovery_link_expired" : "recovery_link_invalid");
      if (rawType === "invite") loginUrl.searchParams.set("error", "invitation_link_invalid");
      throw new Error("invalid_confirmation");
    }
    if (rawType === "recovery") return NextResponse.redirect(new URL("/reset-password", request.url));
    if (rawType === "invite") return NextResponse.redirect(new URL("/configure-account", request.url));

    const { data: rawProfile } = await supabase
      .from("profiles")
      .select("id,first_name,last_name,display_name,role,organization_id,must_change_password,status")
      .eq("id", data.user.id)
      .single();
    if (!rawProfile) throw new Error("missing_profile");

    const profile = rawProfile as AuthProfile;
    await supabase.rpc("log_audit_event", {
      p_event_type: "AUTH_EMAIL_VERIFIED",
      p_entity_type: "AUTH",
      p_entity_id: null,
      p_metadata: {},
    });
    const destinationUrl = new URL(roleDestination(profile.role, profile.must_change_password), request.url);
    destinationUrl.searchParams.set("auth", "session_started");
    return NextResponse.redirect(destinationUrl);
  } catch {
    if (!loginUrl.searchParams.has("error")) loginUrl.searchParams.set("error", "confirmation_failed");
    return NextResponse.redirect(loginUrl);
  }
}
