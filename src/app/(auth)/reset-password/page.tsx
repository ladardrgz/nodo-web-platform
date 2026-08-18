import type { Metadata } from "next";

import { AuthCard } from "@/features/auth/components/AuthCard";
import { AuthPageFrame } from "@/features/auth/components/AuthPageFrame";
import { ChangePasswordForm } from "@/features/auth/components/ChangePasswordForm";
import { requireAuth } from "@/lib/auth/session";

export const metadata: Metadata = { title: "Restablecer contraseña" };

export default async function ResetPasswordPage() {
  await requireAuth({ allowPasswordChange: true });
  return <AuthPageFrame><AuthCard eyebrow="Acceso recuperado" title="Creá una nueva contraseña" description="Elegí una contraseña nueva para volver a acceder a tu cuenta de Nodo."><ChangePasswordForm /></AuthCard></AuthPageFrame>;
}
