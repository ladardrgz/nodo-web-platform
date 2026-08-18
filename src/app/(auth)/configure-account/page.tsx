import type { Metadata } from "next";

import { AuthCard } from "@/features/auth/components/AuthCard";
import { AuthPageFrame } from "@/features/auth/components/AuthPageFrame";
import { ChangePasswordForm } from "@/features/auth/components/ChangePasswordForm";
import { requireAuth } from "@/lib/auth/session";

export const metadata: Metadata = { title: "Configurar cuenta" };

export default async function ConfigureAccountPage() {
  const { email } = await requireAuth({ allowPasswordChange: true });
  return <AuthPageFrame><AuthCard eyebrow="Invitación a Nodo" title="Configurá tu cuenta" description="Fuiste invitado/a a utilizar Nodo. Antes de ingresar, creá una contraseña segura para proteger tu cuenta."><p className="rounded-lg border border-line bg-surface-soft p-3 text-sm text-muted"><strong className="block text-xs uppercase tracking-wide text-ink">Correo</strong><span className="mt-1 block text-ink">{email ?? "Correo asociado a la invitación"}</span></p><div className="mt-5"><ChangePasswordForm /></div></AuthCard></AuthPageFrame>;
}
