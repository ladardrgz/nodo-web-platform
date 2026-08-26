import { Bell, LockKeyhole } from "lucide-react";
import Image from "next/image";
import Link from "next/link";

import { ThemeToggle } from "@/components/ui/ThemeToggle";
import { brand } from "@/config/brand";
import { QuickAccessBar } from "@/features/quick-links/components/QuickAccessBar";
import type { QuickLinkItem } from "@/features/quick-links/config";

export function AppHeader({ organizationSetupCompleted, quickLinks }: { organizationSetupCompleted: boolean; quickLinks: QuickLinkItem[] }) {
  return <header className="sticky top-0 z-30 border-b border-app-border bg-app-surface/95 backdrop-blur"><div className="grid min-h-16 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 px-4 py-2 sm:px-6 lg:px-8"><Link aria-label="Nodo, ir al dashboard" className="flex items-center gap-2 lg:hidden" href="/dashboard"><span className="grid size-9 place-items-center overflow-hidden rounded-lg bg-surface-soft"><Image alt="" className="size-8 object-contain" height={32} priority src={brand.assets.logo} width={32} /></span><strong className="hidden text-sm text-ink sm:block">{brand.shortName}</strong></Link><div className="col-span-3 row-start-2 min-w-0 md:col-span-1 md:col-start-2 md:row-start-1">{organizationSetupCompleted ? <QuickAccessBar configurable links={quickLinks} /> : <div className="inline-flex min-h-9 items-center gap-2 rounded-lg border border-warning/25 bg-warning-soft px-3 text-xs font-bold text-warning"><LockKeyhole className="size-3.5" />Configuración inicial pendiente</div>}</div><div className="col-start-3 row-start-1 flex items-center gap-1.5"><ThemeToggle /><button aria-label="Notificaciones, sin novedades" className="relative grid size-10 place-items-center rounded-lg text-ink-muted transition-colors hover:bg-surface-soft hover:text-ink focus-visible:outline-accent active:bg-line" title="Sin notificaciones nuevas" type="button"><Bell className="size-5" /></button></div></div></header>;
}
