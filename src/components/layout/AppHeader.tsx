import { Bell, Plus } from "lucide-react";
import Image from "next/image";
import Link from "next/link";

import { ButtonLink } from "@/components/ui/Button";
import { ThemeToggle } from "@/components/ui/ThemeToggle";
import { brand } from "@/config/brand";
import type { AuthContext } from "@/types/auth";

export function AppHeader({ context }: { context: AuthContext }) {
  return (
    <header className="sticky top-0 z-30 border-b border-app-border bg-app-surface/95 backdrop-blur">
      <div className="flex min-h-16 items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <Link className="flex items-center gap-2 lg:hidden" href="/dashboard">
          <span className="grid size-9 place-items-center overflow-hidden rounded-lg bg-slate-100">
            <Image alt="" className="size-8 object-contain" height={32} priority src={brand.assets.logo} width={32} />
          </span>
          <strong className="text-sm text-primary">{brand.shortName}</strong>
        </Link>

        <div className="hidden lg:block">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-muted">
            Panel de gestión
          </p>
          <p className="text-sm font-semibold text-primary">{context.profile.display_name || context.email || "Organización activa"}</p>
        </div>

        <div className="flex items-center gap-2">
          <ThemeToggle />
          <button aria-label="Ver notificaciones" className="relative grid size-10 place-items-center rounded-lg text-muted hover:bg-slate-100 hover:text-primary" type="button">
            <Bell className="size-5" />
            <span className="absolute right-2 top-2 size-2 rounded-full bg-danger ring-2 ring-white" />
          </button>
          <ButtonLink className="hidden sm:inline-flex" href="/repairs/new" size="sm">
            <Plus className="size-4" />
            Nueva reparación
          </ButtonLink>
        </div>
      </div>
    </header>
  );
}
