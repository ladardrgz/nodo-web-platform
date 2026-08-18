import { createServerClient } from "@supabase/ssr";
import { type NextRequest, NextResponse } from "next/server";

import { getPublicSupabaseConfig } from "@/lib/supabase/config";

const protectedRoots = [
  "/dashboard",
  "/repairs",
  "/customers",
  "/inventory",
  "/prices",
  "/portal",
  "/superadmin",
  "/change-password",
  "/reset-password",
  "/account-blocked",
  "/forbidden",
];

function isProtectedPath(pathname: string): boolean {
  return protectedRoots.some((root) => pathname === root || pathname.startsWith(`${root}/`));
}

export async function proxy(request: NextRequest) {
  const config = getPublicSupabaseConfig();
  if (!config) return NextResponse.next({ request });
  const hadSupabaseSession = request.cookies.getAll().some((cookie) => cookie.name.startsWith("sb-") && cookie.name.includes("auth-token"));

  let response = NextResponse.next({ request });
  const supabase = createServerClient(config.url, config.publishableKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookiesToSet) => {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  if (!data?.claims?.sub && isProtectedPath(request.nextUrl.pathname)) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    loginUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);
    if (hadSupabaseSession) loginUrl.searchParams.set("auth", "session_expired");
    const redirectResponse = NextResponse.redirect(loginUrl);
    response.cookies.getAll().forEach((cookie) => redirectResponse.cookies.set(cookie));
    return redirectResponse;
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icon.ico|images/.*|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
