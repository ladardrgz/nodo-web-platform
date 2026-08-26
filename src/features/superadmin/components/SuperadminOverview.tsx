import { Activity, Building2, CircleCheck, Settings, Users } from "lucide-react";
import Image from "next/image";

import { ArgentinaGreeting } from "@/features/superadmin/components/ArgentinaGreeting";
import { argentinaGreeting } from "@/lib/argentina-time";

const overviewItems = [
  { key: "organizations", href: "#organizations", title: "Organizaciones", icon: Building2 },
  { key: "users", href: "#users", title: "Usuarios", icon: Users },
  { key: "activity", href: "#activity", title: "Actividad", icon: Activity },
  { key: "system", href: "#system", title: "Sistema", icon: Settings },
] as const;

interface SuperadminOverviewProps {
  firstName: string;
  organizations: number;
  users: number;
  activeUsers: number;
  recentActivity: number;
  systemHealthy: boolean;
}

export function SuperadminOverview({ firstName, organizations, users, activeUsers, recentActivity, systemHealthy }: SuperadminOverviewProps) {
  const greeting = argentinaGreeting();

  const summaries = {
    organizations: `${organizations} registradas`,
    users: `${users} perfiles · ${activeUsers} activos`,
    activity: `${recentActivity} eventos recientes`,
    system: systemHealthy ? "Servicios conectados" : "Requiere revisión",
  };

  return (
    <section className="scroll-mt-32 space-y-4" id="overview">
      <div className="relative isolate min-h-64 overflow-hidden rounded-2xl border border-line bg-brand-surface shadow-[0_18px_50px_rgb(var(--shadow-color)/15%)] sm:min-h-72">
        <Image alt="Equipos de trabajo conectados mediante servicios en la nube" className="object-cover object-[center_68%] opacity-80" fill preload sizes="(min-width: 1024px) calc(100vw - 320px), calc(100vw - 32px)" src="/images/vecteezy_several-work-teams-are-analyzing-data-from-the-cloud-and_.jpg" />
        <div className="absolute inset-0 bg-gradient-to-r from-brand-surface via-brand-surface/95 to-brand-surface/20" />
        <div className="relative z-10 flex min-h-64 max-w-2xl flex-col justify-center p-6 text-brand-contrast sm:min-h-72 sm:p-9 lg:p-10">
          <p className="text-xs font-bold uppercase tracking-[0.18em] text-cyan-brand">Control global de Nodo</p>
          <h1 className="mt-3 text-3xl font-bold tracking-tight sm:text-4xl"><ArgentinaGreeting initialGreeting={greeting} name={firstName} /></h1>
          <p className="mt-4 max-w-lg text-sm leading-6 text-brand-muted sm:text-base">Administrá organizaciones, usuarios y actividad general desde un solo lugar.</p>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {overviewItems.map(({ href, icon: Icon, key, title }) => (
          <a className="group flex min-h-24 items-center gap-3 rounded-xl border border-line bg-surface-raised p-4 shadow-[0_2px_10px_rgb(var(--shadow-color)/7%)] transition hover:-translate-y-0.5 hover:border-accent/35 hover:shadow-[0_10px_28px_rgb(var(--shadow-color)/11%)]" href={href} key={key}>
            <span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent">{key === "system" && systemHealthy ? <CircleCheck className="size-5" /> : <Icon className="size-5" />}</span>
            <span className="min-w-0"><strong className="block text-sm text-ink">{title}</strong><span className="mt-1 block truncate text-xs text-ink-muted">{summaries[key]}</span></span>
          </a>
        ))}
      </div>
    </section>
  );
}
