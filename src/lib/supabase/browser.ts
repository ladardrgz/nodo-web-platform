"use client";

import { createBrowserClient } from "@supabase/ssr";

import { requirePublicSupabaseConfig } from "@/lib/supabase/config";

let browserClient: ReturnType<typeof createBrowserClient> | undefined;

export function createSupabaseBrowserClient() {
  const config = requirePublicSupabaseConfig();
  browserClient ??= createBrowserClient(config.url, config.publishableKey);
  return browserClient;
}
