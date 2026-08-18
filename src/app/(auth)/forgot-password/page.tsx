import type { Metadata } from "next";
import Link from "next/link";

import { AuthCard } from "@/features/auth/components/AuthCard";
import { AuthPageFrame } from "@/features/auth/components/AuthPageFrame";
import { ForgotPasswordForm } from "@/features/auth/components/EmailActionForms";

export const metadata: Metadata = { title: "Recuperar credenciales" };

export default function ForgotPasswordPage() {
  return <AuthPageFrame><AuthCard eyebrow="Recuperación segura" title="Restablecé tu acceso" description="Te enviaremos un enlace de un solo uso. Por seguridad, no confirmamos si el correo está registrado." footer={<Link className="font-bold text-accent" href="/login">Volver al acceso</Link>}><ForgotPasswordForm /></AuthCard></AuthPageFrame>;
}
