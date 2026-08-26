"use client";

import { ArrowRight, BadgeDollarSign, Boxes, LockKeyhole, Smartphone, Users } from "lucide-react";
import Image from "next/image";
import { useEffect, useState } from "react";

import { ButtonLink } from "@/components/ui/Button";
import { argentinaGreeting } from "@/lib/argentina-time";

const lockedFeatures = [
  { label: "Reparaciones", icon: Smartphone },
  { label: "Clientes", icon: Users },
  { label: "Inventario", icon: Boxes },
  { label: "Precios", icon: BadgeDollarSign },
] as const;

export function OwnerSetupWelcome({
  firstName,
  initialGreeting,
}: {
  firstName: string;
  initialGreeting: string;
}) {
  const [greeting, setGreeting] = useState(initialGreeting);

  useEffect(() => {
    const updateGreeting = () => setGreeting(argentinaGreeting());
    const timer = window.setInterval(updateGreeting, 60_000);
    return () => window.clearInterval(timer);
  }, []);

  return (
    <div className="space-y-6">
      <section className="overflow-hidden rounded-2xl border border-border bg-surface-raised shadow-[0_20px_55px_rgb(var(--shadow-color)/12%)]">
        <div className="grid lg:min-h-[390px] lg:grid-cols-[minmax(0,1.15fr)_minmax(320px,0.85fr)]">
          <div className="relative z-10 flex flex-col justify-center p-6 sm:p-10 lg:p-12">
            <span className="inline-flex w-fit items-center gap-2 rounded-full border border-warning/25 bg-warning-soft px-3 py-1.5 text-xs font-bold text-warning">
              <LockKeyhole className="size-3.5" />
              Configuración inicial pendiente
            </span>
            <p className="mt-7 text-sm font-bold uppercase tracking-[0.14em] text-accent">Bienvenido a Nodo</p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight text-primary sm:text-4xl">
              {greeting}, {firstName}
            </h1>
            <p className="mt-5 max-w-xl text-base leading-7 text-muted sm:text-lg">
              Antes de comenzar, necesitamos configurar los datos básicos de tu espacio de trabajo.
            </p>
            <p className="mt-2 max-w-xl text-sm leading-6 text-muted">
              Esta configuración es obligatoria y nos permitirá preparar Nodo para tu organización.
            </p>
            <div className="mt-7">
              <ButtonLink
                className="group shadow-[0_8px_24px_rgb(var(--shadow-color)/14%)] motion-safe:hover:-translate-y-0.5 motion-safe:hover:shadow-[0_12px_30px_rgb(var(--shadow-color)/20%)]"
                href="/initial-setup"
                size="lg"
              >
                Entendido, continuar
                <ArrowRight className="size-4 transition-transform motion-safe:group-hover:translate-x-1" />
              </ButtonLink>
            </div>
          </div>

          <div className="relative min-h-[230px] overflow-hidden border-t border-border bg-white sm:min-h-[280px] lg:min-h-full lg:border-l lg:border-t-0">
            <Image
              alt="Equipo técnico preparando un espacio de trabajo"
              className="object-cover object-[76%_54%]"
              fill
              priority
              sizes="(min-width: 1024px) 38vw, 100vw"
              src="/images/Project_153-06.jpg"
            />
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-white/25 to-transparent lg:bg-gradient-to-r lg:from-white/20 lg:to-transparent" />
          </div>
        </div>
      </section>

      <section aria-labelledby="locked-features-title">
        <div className="mb-4 flex items-center gap-2">
          <LockKeyhole className="size-4 text-muted" />
          <h2 className="font-bold text-primary" id="locked-features-title">
            Funciones bloqueadas hasta completar la configuración
          </h2>
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {lockedFeatures.map(({ icon: Icon, label }) => (
            <article
              aria-label={`${label}: bloqueado`}
              className="flex items-center gap-3 rounded-xl border border-border bg-surface p-4 opacity-70"
              key={label}
            >
              <span className="grid size-10 place-items-center rounded-lg bg-surface-soft text-muted">
                <Icon className="size-5" />
              </span>
              <div>
                <strong className="text-sm text-primary">{label}</strong>
                <p className="mt-0.5 text-xs text-muted">Disponible después</p>
              </div>
              <LockKeyhole aria-hidden="true" className="ml-auto size-4 text-muted" />
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}
