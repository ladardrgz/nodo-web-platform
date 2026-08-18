import { LogOut, Plus, Settings } from "lucide-react";
import Link from "next/link";

import { AppLogo } from "@/components/branding/AppLogo";
import { AdminNavigation } from "@/components/layout/AdminNavigation";
import { ButtonLink } from "@/components/ui/Button";
import { logoutAction } from "@/features/auth/actions";
import type { AuthContext } from "@/types/auth";

export function AppSidebar({ context }: { context: AuthContext }) {
  const name = context.profile.display_name || [context.profile.first_name, context.profile.last_name].filter(Boolean).join(" ") || context.email || "Usuario";
  const initials = name.split(" ").slice(0, 2).map((part) => part[0]).join("").toUpperCase();

  return <aside className="fixed inset-y-0 left-0 z-40 hidden w-72 flex-col bg-app-sidebar text-app-sidebar-text lg:flex"><Link className="flex min-h-20 items-center border-b border-white/10 px-5" href="/dashboard"><AppLogo compact className="text-app-sidebar-text" /></Link><div className="flex-1 overflow-y-auto px-4 py-5"><p className="mb-3 px-3 text-[11px] font-bold uppercase tracking-[0.18em] text-app-sidebar-muted">Operación</p><AdminNavigation /><div className="mt-6"><ButtonLink className="w-full" href="/repairs/new"><Plus className="size-4" />Nueva reparación</ButtonLink></div></div><div className="border-t border-white/10 p-4"><div className="mb-3 flex items-center gap-3 rounded-lg bg-white/8 p-3"><span className="grid size-9 shrink-0 place-items-center rounded-full bg-accent text-xs font-bold">{initials}</span><span className="min-w-0"><strong className="block truncate text-sm">{name}</strong><span className="block text-xs text-app-sidebar-muted">Propietario</span></span></div><div className="grid grid-cols-2 gap-2"><button className="flex min-h-9 items-center justify-center gap-2 rounded-lg text-xs font-semibold text-app-sidebar-muted hover:bg-white/8 hover:text-white" type="button"><Settings className="size-4" />Ajustes</button><form action={logoutAction}><button className="flex min-h-9 w-full items-center justify-center gap-2 rounded-lg text-xs font-semibold text-app-sidebar-muted hover:bg-white/8 hover:text-white" type="submit"><LogOut className="size-4" />Salir</button></form></div></div></aside>;
}
