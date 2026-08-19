export function getLegacyRecoveryRedirect(requestUrl: URL): URL | null {
  if (requestUrl.pathname !== "/") return null;

  const code = requestUrl.searchParams.get("code");
  if (!code) return null;

  const callbackUrl = new URL("/auth/callback", requestUrl.origin);
  callbackUrl.searchParams.set("code", code);
  callbackUrl.searchParams.set("next", "/reset-password");
  return callbackUrl;
}
