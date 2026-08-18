import "server-only";

import { createClient } from "@supabase/supabase-js";

import { AuthConfigurationError } from "@/lib/auth/errors";
import { requirePublicSupabaseConfig } from "@/lib/supabase/config";

export function createSupabaseAdminClient() {
  const { url } = requirePublicSupabaseConfig();
  const secretKey =
    process.env.SUPABASE_SECRET_KEY?.trim() ||
    process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

  if (!secretKey) {
    throw new AuthConfigurationError(
      "Falta SUPABASE_SECRET_KEY (o la clave legacy SUPABASE_SERVICE_ROLE_KEY) en el entorno del servidor.",
    );
  }

  return createClient(url, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
