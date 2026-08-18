import type { Metadata } from "next";
import Link from "next/link";

import { AuthCard } from "@/features/auth/components/AuthCard";
import { AuthPageFrame } from "@/features/auth/components/AuthPageFrame";
import { ResendVerificationForm } from "@/features/auth/components/EmailActionForms";

export const metadata: Metadata = { title: "Verificar correo", robots: { index: false, follow: false } };

export default async function VerifyEmailPage({ searchParams }: { searchParams: Promise<{ email?: string }> }) {
  const { email } = await searchParams;
  return <AuthPageFrame><AuthCard eyebrow="Confirmación pendiente" title="Revisá tu correo" description={<>Te enviamos un enlace de verificación para confirmar tu cuenta de <strong>Nodo</strong>. Después de verificarla, vas a poder iniciar sesión.</>} footer={<Link className="font-bold text-accent" href="/login">Ir a iniciar sesión</Link>}><ResendVerificationForm email={email} /></AuthCard></AuthPageFrame>;
}
