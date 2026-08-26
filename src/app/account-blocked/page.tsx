import { ShieldBan } from "lucide-react";
import { redirect } from "next/navigation";

import { logoutAction } from "@/features/auth/actions";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { roleDestination } from "@/lib/auth/redirects";
import { getOptionalAuthContext } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function AccountBlockedPage() {
  const context = await getOptionalAuthContext();
  if (!context) redirect("/login");
  let organizationSuspended = false;
  if (context.profile.organization_id) {
    const supabase = await createSupabaseServerClient();
    const { data } = await supabase.from("organizations").select("status").eq("id", context.profile.organization_id).maybeSingle();
    organizationSuspended = data?.status === "SUSPENDED";
  }
  if (context.profile.status === "ACTIVE" && !organizationSuspended) redirect(roleDestination(context.profile.role, context.profile.must_change_password));
  return <main className="grid min-h-screen place-items-center bg-background px-4"><div className="max-w-md rounded-2xl border border-border bg-surface p-8 text-center shadow-sm"><span className="mx-auto grid size-16 place-items-center rounded-full bg-danger-soft text-danger"><ShieldBan className="size-7" /></span><h1 className="mt-6 text-2xl font-bold text-primary">{organizationSuspended ? "Organización suspendida" : "Cuenta no disponible"}</h1><p className="mt-3 text-sm leading-6 text-muted">{organizationSuspended ? "El acceso operativo de esta organización está suspendido temporalmente. Sus datos permanecen conservados." : "Tu cuenta está suspendida o deshabilitada. Contactá al soporte de Nodo para revisar el estado."}</p><form action={logoutAction} className="mt-6"><SubmitButton label="Cerrar sesión" pendingLabel="Cerrando sesión…" /></form></div></main>;
}
