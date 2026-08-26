"use client";

import { Activity, Building2, Gauge, Settings, UserCircle2, Users } from "lucide-react";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import { AppLogo } from "@/components/branding/AppLogo";
import { ThemeToggle } from "@/components/ui/ThemeToggle";
import { LogoutSubmitButton } from "@/features/auth/components/LogoutSubmitButton";
import { logoutAction } from "@/features/auth/actions";
import type { AuthContext } from "@/types/auth";

const navigation = [
  { href: "/superadmin#overview", label: "Resumen", icon: Gauge },
  { href: "/superadmin#organizations", label: "Organizaciones", icon: Building2 },
  { href: "/superadmin#users", label: "Usuarios", icon: Users },
  { href: "/superadmin/activity", label: "Actividad", icon: Activity },
  { href: "/superadmin#system", label: "Estado del sistema", icon: Settings },
  { href: "/superadmin/profile", label: "Mi perfil", icon: UserCircle2 },
] as const;

export function SuperadminShell({ children, context }: { children: ReactNode; context: AuthContext }) {
  const pathname = usePathname();
  const name = context.profile.display_name || [context.profile.first_name, context.profile.last_name].filter(Boolean).join(" ") || context.email || "Administrador global";
  const initials = name.split(" ").slice(0, 2).map((part) => part[0]).join("").toUpperCase();

  return (
    <div className="app-shell app-background min-h-screen">
      <aside className="fixed inset-y-0 left-0 z-40 hidden w-64 flex-col bg-app-sidebar text-app-sidebar-text lg:flex">
        <a className="flex min-h-20 items-center border-b border-white/10 px-5" href="/superadmin"><AppLogo compact className="text-app-sidebar-text" /></a>
        <div className="flex-1 px-4 py-5">
          <p className="mb-3 px-3 text-[11px] font-bold uppercase tracking-[0.18em] text-app-sidebar-muted">Administración global</p>
          <nav aria-label="Navegación de superadministración" className="space-y-1">
            {navigation.map((item, index) => { const Icon = item.icon; const active = item.href.startsWith("/superadmin/") ? pathname === item.href || pathname.startsWith(`${item.href}/`) : index === 0 && pathname === "/superadmin"; return <a aria-current={active ? "page" : undefined} className={`flex min-h-11 items-center gap-3 rounded-lg px-3 text-sm font-semibold transition-colors ${active ? "bg-app-sidebar-active text-app-sidebar-text" : "text-app-sidebar-muted hover:bg-white/8 hover:text-white"}`} href={item.href} key={item.href}><Icon className="size-[18px]" />{item.label}</a>; })}
          </nav>
        </div>
        <div className="border-t border-white/10 p-4">
          <div className="mb-3 flex items-center justify-between gap-3 px-2 text-xs font-semibold text-app-sidebar-muted"><span>Apariencia</span><ThemeToggle /></div>
          <div className="mb-3 flex items-center gap-3 rounded-lg bg-white/8 p-3"><span className="grid size-9 shrink-0 place-items-center rounded-full bg-accent text-xs font-bold">{initials}</span><span className="min-w-0"><strong className="block truncate text-sm">{name}</strong><span className="block text-xs text-app-sidebar-muted">Superadministrador</span></span></div>
          <form action={logoutAction}><LogoutSubmitButton className="min-h-10 w-full rounded-lg text-sm font-semibold text-app-sidebar-muted hover:bg-white/8 hover:text-white" /></form>
        </div>
      </aside>

      <div className="min-h-screen lg:pl-64">
        <header className="sticky top-0 z-30 border-b border-app-border bg-app-surface/95 backdrop-blur lg:hidden">
          <div className="flex min-h-16 items-center justify-between gap-3 px-4"><AppLogo compact className="text-primary" /><div className="ml-auto text-right"><strong className="block max-w-36 truncate text-xs text-primary">{name}</strong><span className="text-[11px] text-muted">Superadministrador</span></div><ThemeToggle /></div>
          <nav aria-label="Navegación de superadministración" className="flex overflow-x-auto border-t border-border px-2">
            {navigation.map((item) => { const Icon = item.icon; const active = item.href.startsWith("/superadmin/") ? pathname === item.href || pathname.startsWith(`${item.href}/`) : item.href === "/superadmin#overview" && pathname === "/superadmin"; return <a aria-current={active ? "page" : undefined} className={`flex min-h-12 shrink-0 items-center gap-2 px-3 text-xs font-semibold ${active ? "text-accent" : "text-muted hover:text-accent"}`} href={item.href} key={item.href}><Icon className="size-4" />{item.label}</a>; })}
          </nav>
        </header>
        <main className="mx-auto w-full max-w-[1500px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8">{children}</main>
      </div>
    </div>
  );
}
