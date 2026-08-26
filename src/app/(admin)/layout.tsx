import type { ReactNode } from "react";

import { AdminShell } from "@/components/layout/AdminShell";
import type { QuickLinkItem } from "@/features/quick-links/config";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const { context, organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  let quickLinks: QuickLinkItem[] = [];
  if (organization.initial_setup_completed) {
    const supabase = await createSupabaseServerClient();
    const { data } = await supabase.from("user_quick_links").select("id,service,url,enabled").eq("user_id", context.userId);
    quickLinks = (data ?? []) as QuickLinkItem[];
  }
  return <AdminShell context={context} organizationSetupCompleted={organization.initial_setup_completed} quickLinks={quickLinks}>{children}</AdminShell>;
}
