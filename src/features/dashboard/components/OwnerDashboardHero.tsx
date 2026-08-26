import { Plus } from "lucide-react";
import Image from "next/image";

import { ButtonLink } from "@/components/ui/Button";

interface OwnerDashboardHeroProps {
  firstName: string;
  greeting: string;
  logoUrl: string | null;
  organizationName: string;
  showPrimaryAction: boolean;
}

export function OwnerDashboardHero({
  firstName,
  greeting,
  logoUrl,
  organizationName,
  showPrimaryAction,
}: OwnerDashboardHeroProps) {
  const initials = organizationName
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase() || "N";

  return (
    <section className="relative overflow-hidden rounded-2xl border border-app-border bg-app-card px-5 py-5 shadow-[0_8px_30px_rgb(var(--shadow-color)/7%)] sm:px-6 sm:py-6 lg:px-7">
      <div aria-hidden="true" className="absolute -right-16 -top-20 size-48 rounded-full bg-accent/7 blur-3xl" />
      <div className="relative flex flex-col gap-5 sm:flex-row sm:items-center">
        <div className="flex min-w-0 flex-1 items-center gap-4 sm:gap-5">
          <div className="relative grid size-16 shrink-0 place-items-center overflow-hidden rounded-xl border border-app-border bg-app-surface-soft text-lg font-bold text-accent shadow-sm sm:size-20">
            {logoUrl ? <Image alt={`Logo de ${organizationName}`} className="object-contain p-2" fill priority sizes="80px" src={logoUrl} unoptimized /> : <span aria-label={`Iniciales de ${organizationName}`}>{initials}</span>}
          </div>
          <div className="min-w-0">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">Inicio operativo</p>
            <h1 className="mt-1.5 text-xl font-bold tracking-tight text-app-text sm:text-2xl">{greeting}, {firstName}</h1>
            <p className="mt-1 text-sm text-app-text-secondary sm:text-base">Esto está pasando hoy en <strong className="font-bold text-app-text">{organizationName}</strong>.</p>
          </div>
        </div>
        {showPrimaryAction ? <ButtonLink className="w-full shrink-0 sm:w-auto" href="/repairs/new"><Plus aria-hidden="true" className="size-4" />Nueva reparación</ButtonLink> : null}
      </div>
    </section>
  );
}
