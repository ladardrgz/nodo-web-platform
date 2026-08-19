import { AuthConfigurationError } from "@/lib/auth/errors";
export { getAppUrl } from "@/lib/supabase/app-url";

export interface PublicSupabaseConfig {
  url: string;
  publishableKey: string;
}

export function getPublicSupabaseConfig(): PublicSupabaseConfig | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

  if (!url || !publishableKey) return null;
  return { url, publishableKey };
}

export function requirePublicSupabaseConfig(): PublicSupabaseConfig {
  const config = getPublicSupabaseConfig();
  if (!config) throw new AuthConfigurationError();
  return config;
}
