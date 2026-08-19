export function getLegacyRecoveryRedirect(requestUrl: URL): URL | null {
  if (requestUrl.pathname !== "/") return null;

  const code = requestUrl.searchParams.get("code");
  if (!code) return null;

  const confirmUrl = new URL("/auth/confirm", requestUrl.origin);
  confirmUrl.searchParams.set("code", code);
  return confirmUrl;
}
