"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LockKeyhole } from "lucide-react";

import { adminNavigation } from "@/config/navigation";
import { cn } from "@/lib/cn";

interface AdminNavigationProps {
  mobile?: boolean;
  organizationSetupCompleted: boolean;
}

function isActivePath(pathname: string, href: string): boolean {
  return pathname === href || (href !== "/dashboard" && pathname.startsWith(`${href}/`));
}

export function AdminNavigation({ mobile = false, organizationSetupCompleted }: AdminNavigationProps) {
  const pathname = usePathname();

  return (
    <nav
      aria-label={mobile ? "Navegación móvil" : "Navegación principal"}
      className={mobile ? "grid grid-cols-5" : "space-y-1"}
    >
      {adminNavigation.map((item) => {
        const active = isActivePath(pathname, item.href);
        const Icon = item.icon;
        const locked = !organizationSetupCompleted && item.href !== "/dashboard";

        const content = <><Icon aria-hidden="true" className="size-5" /><span>{item.label}</span>{locked ? <LockKeyhole aria-hidden="true" className={cn("size-3.5", !mobile && "ml-auto")} /> : null}{!mobile && locked ? <span className="sr-only">Bloqueado</span> : null}</>;
        if (locked) {
          return <span aria-disabled="true" className={cn("flex cursor-not-allowed items-center opacity-55", mobile ? "min-h-16 flex-col justify-center gap-1 px-1 text-[10px] font-semibold text-slate-500" : "min-h-11 gap-3 rounded-lg px-3 text-sm font-semibold text-app-sidebar-muted")} key={item.href} title="Completá la configuración inicial para habilitar esta función.">{content}</span>;
        }

        return (
          <Link
            aria-current={active ? "page" : undefined}
            className={cn(
              "group flex items-center transition-colors",
              mobile
                ? "min-h-16 flex-col justify-center gap-1 px-1 text-[10px] font-semibold"
                : "min-h-11 gap-3 rounded-lg px-3 text-sm font-semibold",
              active
                ? mobile
                  ? "text-accent"
                  : "bg-app-sidebar-active text-app-sidebar-text"
                : mobile
                  ? "text-slate-500 hover:text-primary"
                  : "text-app-sidebar-muted hover:bg-white/8 hover:text-white",
            )}
            href={item.href}
            key={item.href}
          >
            {content}
          </Link>
        );
      })}
    </nav>
  );
}
