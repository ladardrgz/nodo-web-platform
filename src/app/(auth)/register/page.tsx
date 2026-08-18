import type { Metadata } from "next";
import Link from "next/link";

import { AuthCard } from "@/features/auth/components/AuthCard";
import { AuthPageFrame } from "@/features/auth/components/AuthPageFrame";
import { RegisterForm } from "@/features/auth/components/RegisterForm";

export const metadata: Metadata = { title: "Crear cuenta", robots: { index: false, follow: false } };

export default function RegisterPage() {
  return <AuthPageFrame><AuthCard eyebrow="Nueva cuenta" title="Creá tu cuenta" description="Empezá con un acceso de cliente. Te vamos a enviar un enlace para confirmar tu correo." footer={<>¿Ya tenés cuenta? <Link className="font-bold text-accent" href="/login">Iniciá sesión</Link></>}><RegisterForm /></AuthCard></AuthPageFrame>;
}
