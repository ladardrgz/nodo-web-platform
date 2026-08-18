import { ShieldBan } from "lucide-react";
import { redirect } from "next/navigation";

import { logoutAction } from "@/features/auth/actions";
import { roleDestination } from "@/lib/auth/redirects";
import { getOptionalAuthContext } from "@/lib/auth/session";

export default async function AccountBlockedPage() {
  const context = await getOptionalAuthContext();
  if (!context) redirect("/login");
  if (context.profile.status === "ACTIVE") redirect(roleDestination(context.profile.role, context.profile.must_change_password));
  return <main className="grid min-h-screen place-items-center bg-background px-4"><div className="max-w-md rounded-2xl border border-border bg-white p-8 text-center shadow-sm"><span className="mx-auto grid size-16 place-items-center rounded-full bg-red-50 text-danger"><ShieldBan className="size-7" /></span><h1 className="mt-6 text-2xl font-bold text-primary">Cuenta no disponible</h1><p className="mt-3 text-sm leading-6 text-muted">Tu cuenta está suspendida o deshabilitada. Contactá al soporte de Nodo para revisar el estado.</p><form action={logoutAction} className="mt-6"><button className="min-h-11 rounded-lg bg-accent px-5 text-sm font-semibold text-white" type="submit">Cerrar sesión</button></form></div></main>;
}
