import { AuthConfigurationError } from "@/lib/auth/errors";
import { normalizeSupabaseUrl } from "@/lib/supabase/supabase-url";
export { getAppUrl } from "@/lib/supabase/app-url";

export interface PublicSupabaseConfig {
  url: string;
  publishableKey: string;
}

export function getPublicSupabaseConfig(): PublicSupabaseConfig | null {
  const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

  if (!rawUrl || !publishableKey) return null;
  return { url: normalizeSupabaseUrl(rawUrl), publishableKey };
}

export function requirePublicSupabaseConfig(): PublicSupabaseConfig {
  const config = getPublicSupabaseConfig();
  if (!config) throw new AuthConfigurationError();
  return config;
}
