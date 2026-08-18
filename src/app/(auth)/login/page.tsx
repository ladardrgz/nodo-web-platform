import { CircuitBoard, ShieldCheck } from "lucide-react";
import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";

import { AppLogo } from "@/components/branding/AppLogo";
import { PublicAuthHeader } from "@/components/public/PublicAuthHeader";
import { brand } from "@/config/brand";
import { LoginForm } from "@/features/auth/components/LoginForm";
import { isGoogleAuthEnabled } from "@/lib/auth/features";
import { roleDestination, sanitizeInternalRedirect } from "@/lib/auth/redirects";
import { getOptionalAuthContext } from "@/lib/auth/session";
import { getPublicSupabaseConfig } from "@/lib/supabase/config";

export const metadata: Metadata = { title: "Iniciar sesión", robots: { index: false, follow: false } };

const errorMessages: Record<string, string> = {
  callback_failed: "No pudimos completar el acceso. El enlace puede haber vencido.",
  confirmation_failed: "No pudimos verificar el correo. Solicitá un enlace nuevo.",
  invalid_confirmation: "El enlace de verificación no es válido.",
  missing_code: "El proveedor no devolvió un código de acceso válido.",
  oauth_failed: "No pudimos iniciar sesión con Google.",
  rate_limited: "Demasiados intentos. Esperá unos minutos antes de volver a probar.",
  session_expired: "Tu sesión expiró. Volvé a iniciar sesión.",
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string; error?: string }> }) {
  const context = await getOptionalAuthContext();
  if (context) redirect(roleDestination(context.profile.role, context.profile.must_change_password));

  const params = await searchParams;
  const nextPath = sanitizeInternalRedirect(params.next) ?? undefined;
  const configurationMissing = !getPublicSupabaseConfig();
  const googleAuthEnabled = isGoogleAuthEnabled();

  return (
    <div className="public-shell min-h-screen"><PublicAuthHeader /><main className="flex min-h-[calc(100vh-4rem)] items-center justify-center px-4 py-5 sm:px-6 sm:py-6">
      <section className="grid w-full max-w-5xl overflow-hidden rounded-[1.25rem] border border-line bg-surface-raised shadow-[0_16px_45px_rgb(var(--shadow-color)/11%)] lg:grid-cols-[1fr_0.92fr]">
        <div className="relative min-h-44 overflow-hidden bg-brand-surface p-5 text-white sm:min-h-52 sm:p-7 lg:min-h-[540px] lg:p-8">
          <Image alt="Mesa de trabajo tecnológica de Nodo" className="object-cover" fill priority sizes="(min-width: 1024px) 55vw, 100vw" src={brand.assets.loginBackground} />
          <div className="absolute inset-0 bg-[linear-gradient(140deg,rgba(20,31,46,0.96),rgba(20,31,46,0.68)_58%,rgba(20,31,46,0.42))]" />
          <div className="relative z-10 flex h-full min-h-32 flex-col justify-between sm:min-h-38 lg:min-h-[476px]">
            <AppLogo className="text-white" />
            <div className="max-w-md">
              <div className="hidden items-center gap-2 text-xs font-bold uppercase tracking-[0.18em] text-blue-200 sm:flex"><CircuitBoard className="size-4" />Operación conectada</div>
              <h1 className="mt-3 max-w-sm text-2xl font-bold leading-tight tracking-tight sm:text-3xl">Cada servicio, organizado de principio a fin.</h1>
              <p className="mt-3 hidden max-w-sm text-sm leading-6 text-brand-muted sm:block">Trazabilidad clara para el taller y una experiencia confiable para cada cliente.</p>
              <div className="mt-6 hidden items-center gap-2 text-xs font-semibold text-brand-subtle lg:flex"><ShieldCheck className="size-4 text-cyan-300" />Acceso protegido con Supabase Auth</div>
            </div>
          </div>
        </div>

        <div className="flex items-center px-5 py-6 sm:px-8 sm:py-7 lg:px-10">
          <div className="mx-auto w-full max-w-[390px]">
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-accent">Inicio de sesión en Nodo</p>
            <h2 className="mt-2 text-2xl font-bold tracking-tight text-ink">¡Bienvenido!</h2>
            <p className="mt-2 text-sm leading-6 text-ink-secondary">Ingresá para continuar a tu espacio de <strong>Nodo</strong>.</p>

            <div className="mt-5">
              <LoginForm configurationMissing={configurationMissing} googleAuthEnabled={googleAuthEnabled} initialMessage={params.error ? errorMessages[params.error] : undefined} nextPath={nextPath} />
            </div>

            <p className="mt-5 border-t border-border pt-4 text-center text-sm text-muted">¿Todavía no tenés cuenta? <Link className="font-bold text-accent hover:text-accent-strong" href="/register">Crearme una cuenta</Link></p>
          </div>
        </div>
      </section>
    </main></div>
  );
}
