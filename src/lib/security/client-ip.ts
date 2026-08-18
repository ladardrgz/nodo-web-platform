import type { ReadonlyHeaders } from "next/dist/server/web/spec-extension/adapters/headers";

export type TrustedProxyProvider = "none" | "vercel" | "cloudflare" | "single-proxy";

function firstAddress(value: string | null): string | null {
  const address = value?.split(",")[0]?.trim();
  return address && address.length <= 64 ? address : null;
}

export function getClientIp(headersList: Pick<ReadonlyHeaders, "get">): string | null {
  const provider = (process.env.TRUSTED_PROXY_PROVIDER ?? "none") as TrustedProxyProvider;

  if (provider === "cloudflare") return firstAddress(headersList.get("cf-connecting-ip"));
  if (provider === "vercel") {
    return firstAddress(headersList.get("x-vercel-forwarded-for") ?? headersList.get("x-forwarded-for"));
  }
  if (provider === "single-proxy") return firstAddress(headersList.get("x-forwarded-for"));
  return null;
}
