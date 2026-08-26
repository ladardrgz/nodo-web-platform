import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export const ORGANIZATION_LOGO_BUCKET = "organization-logos";

export async function getOrganizationLogoSignedUrl(logoPath: string | null): Promise<string | null> {
  if (!logoPath) return null;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.storage.from(ORGANIZATION_LOGO_BUCKET).createSignedUrl(logoPath, 3600);
  return error ? null : data.signedUrl;
}
