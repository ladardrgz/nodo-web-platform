import { timingSafeEqual } from "node:crypto";

import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

function authorized(request: Request): boolean {
  const configured = (process.env.CRON_SECRET || process.env.ACCOUNT_DELETION_CRON_SECRET)?.trim();
  const provided = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!configured || !provided) return false;
  const expectedBuffer = Buffer.from(configured);
  const providedBuffer = Buffer.from(provided);
  return expectedBuffer.length === providedBuffer.length && timingSafeEqual(expectedBuffer, providedBuffer);
}

async function processDeletions(request: Request) {
  if (!authorized(request)) return Response.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const admin = createSupabaseAdminClient();
    const { error: finalizeError } = await admin.rpc("finalize_due_account_deletions");
    if (finalizeError) throw finalizeError;

    const { data: pendingCleanup, error: cleanupReadError } = await admin
      .from("account_deletion_requests")
      .select("id,subject_type,organization_id,target_user_id")
      .eq("status", "COMPLETED")
      .eq("auth_cleanup_completed", false)
      .limit(100);
    if (cleanupReadError) throw cleanupReadError;

    let cleaned = 0;
    for (const item of pendingCleanup ?? []) {
      const userIds = new Set<string>();
      if (item.subject_type === "CUSTOMER_ACCOUNT" && item.target_user_id) userIds.add(item.target_user_id);
      if (item.subject_type === "ORGANIZATION" && item.organization_id) {
        const { data: profiles, error: profilesError } = await admin.from("profiles").select("id").eq("organization_id", item.organization_id);
        if (profilesError) continue;
        profiles?.forEach((profile) => userIds.add(profile.id));
      }

      let complete = true;
      for (const userId of userIds) {
        const { error } = await admin.auth.admin.deleteUser(userId);
        if (error && !error.message.toLowerCase().includes("not found")) complete = false;
      }
      if (!complete) continue;
      const { error: markError } = await admin.rpc("mark_deletion_auth_cleanup", { p_request_id: item.id });
      if (!markError) cleaned += 1;
    }

    return Response.json({ processed: pendingCleanup?.length ?? 0, authCleanupsCompleted: cleaned });
  } catch {
    return Response.json({ error: "Account deletion processing failed" }, { status: 500 });
  }
}

export async function GET(request: Request) {
  return processDeletions(request);
}

export async function POST(request: Request) {
  return processDeletions(request);
}
