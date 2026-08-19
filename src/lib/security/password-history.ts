import "server-only";

import { createHmac, timingSafeEqual } from "node:crypto";

import { AuthConfigurationError } from "@/lib/auth/errors";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

const LIMIT = 5;

function fingerprint(password: string): string {
  const pepper = process.env.PASSWORD_HISTORY_PEPPER?.trim();
  if (!pepper || pepper.length < 32) {
    throw new AuthConfigurationError("Falta PASSWORD_HISTORY_PEPPER de 32 caracteres o más en el entorno del servidor.");
  }
  return createHmac("sha256", pepper).update(password, "utf8").digest("hex");
}

export async function assertPasswordIsNew(userId: string, password: string) {
  const candidate = fingerprint(password);
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin
    .from("password_history")
    .select("fingerprint")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(LIMIT);
  if (error) throw error;
  const reused = (data ?? []).some(({ fingerprint: stored }) => {
    const left = Buffer.from(stored, "hex");
    const right = Buffer.from(candidate, "hex");
    return left.length === right.length && timingSafeEqual(left, right);
  });
  if (reused) throw new Error("PASSWORD_REUSED");
}

export async function rememberPassword(userId: string, password: string) {
  const admin = createSupabaseAdminClient();
  const { error } = await admin.from("password_history").insert({ user_id: userId, fingerprint: fingerprint(password) });
  if (error) throw error;
  const { data: stale, error: staleError } = await admin
    .from("password_history")
    .select("id")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .range(LIMIT, 1000);
  if (staleError) throw staleError;
  if (stale?.length) {
    const { error: deleteError } = await admin.from("password_history").delete().in("id", stale.map((row) => row.id));
    if (deleteError) throw deleteError;
  }
}
