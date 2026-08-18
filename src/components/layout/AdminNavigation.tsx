"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { adminNavigation } from "@/config/navigation";
import { cn } from "@/lib/cn";

interface AdminNavigationProps {
  mobile?: boolean;
}

function isActivePath(pathname: string, href: string): boolean {
  return pathname === href || (href !== "/dashboard" && pathname.startsWith(`${href}/`));
}

export function AdminNavigation({ mobile = false }: AdminNavigationProps) {
  const pathname = usePathname();

  return (
    <nav
      aria-label={mobile ? "Navegación móvil" : "Navegación principal"}
      className={mobile ? "grid grid-cols-5" : "space-y-1"}
    >
      {adminNavigation.map((item) => {
        const active = isActivePath(pathname, item.href);
        const Icon = item.icon;

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
            <Icon aria-hidden="true" className={mobile ? "size-5" : "size-5"} />
            <span>{item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
