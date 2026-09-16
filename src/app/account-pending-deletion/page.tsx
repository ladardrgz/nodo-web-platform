import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { AppLogo } from "@/components/branding/AppLogo";
import { Card } from "@/components/ui/Card";
import { PendingDeletionPanel } from "@/features/account-deletion/components/PendingDeletionPanel";
import type { PendingDeletion } from "@/features/account-deletion/types";
import { logoutAction } from "@/features/auth/actions";
import { LogoutSubmitButton } from "@/features/auth/components/LogoutSubmitButton";
import { requireAuth } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Baja pendiente" };

export default async function AccountPendingDeletionPage() {
  await requireAuth({ allowPendingDeletion: true });
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("get_my_pending_deletion");
  const request = (Array.isArray(data) ? data[0] : null) as PendingDeletion | undefined;
  if (error || !request) redirect("/account-blocked");

  return <main className="app-background min-h-screen px-4 py-8 sm:py-14"><div className="mx-auto max-w-3xl"><div className="mb-6 flex items-center justify-between gap-4"><AppLogo /><form action={logoutAction}><LogoutSubmitButton /></form></div><Card className="p-2 sm:p-3"><PendingDeletionPanel request={request} /></Card></div></main>;
}
