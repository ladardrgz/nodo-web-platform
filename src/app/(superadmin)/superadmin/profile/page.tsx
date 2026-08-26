import { UserCircle2 } from "lucide-react";
import type { Metadata } from "next";

import { SuperadminProfile } from "@/features/superadmin/components/SuperadminProfile";
import { MfaSecurity } from "@/features/superadmin/components/MfaSecurity";
import { SecurityHistory } from "@/features/superadmin/components/SecurityHistory";
import { SessionsSecurity } from "@/features/superadmin/components/SessionsSecurity";
import { formatArgentinaDateTime } from "@/lib/argentina-time";
import { requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Mi perfil · Superadmin" };

export default async function SuperadminProfilePage() {
  const context = await requireRole(["SUPERADMIN"]);
  const supabase = await createSupabaseServerClient();
  const securityTypes = ["AUTH_LOGIN", "AUTH_LOGOUT", "AUTH_PASSWORD_CHANGED", "SUPERADMIN_PASSWORD_CHANGED", "PASSWORD_CHANGED", "SUPERADMIN_PASSWORD_RESET_REQUESTED", "PASSWORD_RESET_REQUESTED", "MFA_ENROLL_STARTED", "MFA_ENABLED", "MFA_DISABLED", "OTHER_SESSIONS_REVOKED"];
  const [{ data: latestPasswordEvent }, { data: latestAccessEvent }, { data: securityEvents }] = await Promise.all([
    supabase.from("audit_events").select("created_at").eq("actor_user_id", context.userId).in("event_type", ["SUPERADMIN_PASSWORD_CHANGED", "AUTH_PASSWORD_CHANGED", "PASSWORD_CHANGED"]).order("created_at", { ascending: false }).limit(1).maybeSingle(),
    supabase.from("audit_events").select("created_at").eq("actor_user_id", context.userId).eq("event_type", "AUTH_LOGIN").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    supabase.from("audit_events").select("id,event_type,created_at,result").eq("actor_user_id", context.userId).in("event_type", securityTypes).order("created_at", { ascending: false }).limit(100),
  ]);
  const firstName = context.profile.first_name ?? "";
  const lastName = context.profile.last_name ?? "";
  const displayName = context.profile.display_name || [firstName, lastName].filter(Boolean).join(" ");

  return (
    <div className="space-y-6">
      <header className="flex items-start gap-4"><span className="grid size-12 shrink-0 place-items-center rounded-xl bg-accent-soft text-accent"><UserCircle2 className="size-6" /></span><div><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Cuenta global</p><h1 className="mt-1 text-2xl font-bold text-ink">Mi perfil</h1><p className="mt-2 max-w-2xl text-sm leading-6 text-ink-muted">Administrá tus datos personales y la seguridad de tu acceso SUPERADMIN.</p></div></header>
      <SuperadminProfile email={context.email ?? "Correo no disponible"} lastPasswordUpdate={latestPasswordEvent?.created_at ? formatArgentinaDateTime(latestPasswordEvent.created_at) : null} profile={{ firstName, lastName, displayName }} />
      <div className="grid gap-5 xl:grid-cols-2"><MfaSecurity /><SessionsSecurity lastAccess={latestAccessEvent?.created_at ? formatArgentinaDateTime(latestAccessEvent.created_at) : null} /></div>
      <SecurityHistory events={(securityEvents ?? []).map((event) => ({ id: event.id, eventType: event.event_type, createdAt: event.created_at, result: event.result }))} />
    </div>
  );
}
