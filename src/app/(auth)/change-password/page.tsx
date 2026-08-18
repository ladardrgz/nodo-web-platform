import type { Metadata } from "next";

import { AuthCard } from "@/features/auth/components/AuthCard";
import { AuthPageFrame } from "@/features/auth/components/AuthPageFrame";
import { ChangePasswordForm } from "@/features/auth/components/ChangePasswordForm";
import { requireAuth } from "@/lib/auth/session";

export const metadata: Metadata = { title: "Cambiar contraseña" };

export default async function ChangePasswordPage() {
  const { profile } = await requireAuth({ allowPasswordChange: true });
  return <AuthPageFrame><AuthCard eyebrow="Seguridad de la cuenta" title={profile.must_change_password ? "Cambio obligatorio" : "Cambiar contraseña"} description={profile.must_change_password ? "Tu acceso fue creado con una credencial temporal. Definí una contraseña personal antes de continuar." : "Definí una contraseña nueva y segura para tu cuenta."}><ChangePasswordForm /></AuthCard></AuthPageFrame>;
}
