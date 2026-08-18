import "server-only";

import { headers } from "next/headers";

import { AuthConfigurationError } from "@/lib/auth/errors";
import { getClientIp } from "@/lib/security/client-ip";
import { createRateLimitKey, type AuthRateLimitAction } from "@/lib/security/rate-limit-key";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export interface RateLimitDecision {
  allowed: boolean;
  retryAfterSeconds: number;
}

function makeRateLimitKey(action: AuthRateLimitAction, dimension: "identifier" | "ip", value: string): string {
  const secret = process.env.AUTH_RATE_LIMIT_SECRET?.trim();
  if (!secret || secret.length < 32) {
    throw new AuthConfigurationError("AUTH_RATE_LIMIT_SECRET debe tener al menos 32 caracteres.");
  }

  return createRateLimitKey(secret, action, dimension, value);
}

async function consume(action: AuthRateLimitAction, keyHash: string): Promise<RateLimitDecision> {
  const supabase = createSupabaseAdminClient();
  const { data, error } = await supabase.rpc("consume_auth_rate_limit", {
    p_action: action,
    p_key_hash: keyHash,
  });

  if (error) throw new Error("No se pudo verificar el límite de intentos.");
  const row = Array.isArray(data) ? data[0] : data;

  return {
    allowed: Boolean(row?.allowed),
    retryAfterSeconds: Number(row?.retry_after_seconds ?? 0),
  };
}

export async function enforceAuthRateLimit(
  action: AuthRateLimitAction,
  identifier: string,
): Promise<RateLimitDecision> {
  const headersList = await headers();
  const clientIp = getClientIp(headersList);
  const keys = [makeRateLimitKey(action, "identifier", identifier)];
  if (clientIp) keys.push(makeRateLimitKey(action, "ip", clientIp));

  for (const key of keys) {
    const decision = await consume(action, key);
    if (!decision.allowed) return decision;
  }

  return { allowed: true, retryAfterSeconds: 0 };
}

export async function enforceAuthIpRateLimit(action: AuthRateLimitAction): Promise<RateLimitDecision> {
  const headersList = await headers();
  const clientIp = getClientIp(headersList);
  if (!clientIp) return { allowed: true, retryAfterSeconds: 0 };
  return consume(action, makeRateLimitKey(action, "ip", clientIp));
}

export async function resetAuthRateLimit(action: AuthRateLimitAction, identifier: string): Promise<void> {
  const headersList = await headers();
  const clientIp = getClientIp(headersList);
  const keys = [makeRateLimitKey(action, "identifier", identifier)];
  if (clientIp) keys.push(makeRateLimitKey(action, "ip", clientIp));
  const supabase = createSupabaseAdminClient();
  await Promise.all(keys.map((keyHash) => supabase.rpc("reset_auth_rate_limit", { p_action: action, p_key_hash: keyHash })));
}
