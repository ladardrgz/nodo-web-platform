import { NextResponse, type NextRequest } from "next/server";

import { isGoogleAuthEnabled } from "@/lib/auth/features";
import { sanitizeInternalRedirect } from "@/lib/auth/redirects";
import { enforceAuthIpRateLimit } from "@/lib/security/rate-limit";
import { getAppUrl } from "@/lib/supabase/config";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const loginUrl = new URL("/login", request.url);

  if (!isGoogleAuthEnabled()) {
    return NextResponse.redirect(loginUrl);
  }

  try {
    const limit = await enforceAuthIpRateLimit("OAUTH");
    if (!limit.allowed) {
      loginUrl.searchParams.set("error", "rate_limited");
      return NextResponse.redirect(loginUrl);
    }

    const next = sanitizeInternalRedirect(request.nextUrl.searchParams.get("next"));
    const callback = new URL("/auth/callback", getAppUrl());
    if (next) callback.searchParams.set("next", next);

    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: callback.toString() },
    });
    if (error || !data.url) throw new Error("oauth_failed");
    return NextResponse.redirect(data.url);
  } catch {
    loginUrl.searchParams.set("error", "oauth_failed");
    return NextResponse.redirect(loginUrl);
  }
}
