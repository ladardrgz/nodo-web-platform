"use client";

import { LockKeyhole } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

import { getNavigationForRole } from "@/config/navigation";
import { cn } from "@/lib/cn";
import type { AppRole } from "@/types/auth";

interface AdminNavigationProps {
  mobile?: boolean;
  collapsed?: boolean;
  organizationSetupCompleted: boolean;
  role: AppRole;
}

function isActivePath(
  pathname: string,
  href: string,
  currentHash: string,
): boolean {
  const [path, hash] = href.split("#");
  if (hash) return pathname === path && currentHash === `#${hash}`;
  return (
    pathname === href ||
    (href !== "/dashboard" && pathname.startsWith(`${href}/`))
  );
}

export function AdminNavigation({
  mobile = false,
  collapsed = false,
  organizationSetupCompleted,
  role,
}: AdminNavigationProps) {
  const pathname = usePathname();
  const [currentHash, setCurrentHash] = useState("");
  const navigation = getNavigationForRole(role);

  useEffect(() => {
    const syncHash = () => setCurrentHash(window.location.hash || "#overview");
    syncHash();
    window.addEventListener("hashchange", syncHash);
    return () => window.removeEventListener("hashchange", syncHash);
  }, []);

  return (
    <nav
      aria-label={
        mobile ? "Navegación móvil" : "Navegación principal"
      }
      className={mobile ? "flex overflow-x-auto" : "space-y-1"}
    >
      {navigation.map((item) => {
        const active = isActivePath(pathname, item.href, currentHash);
        const Icon = item.icon;

        const locked =
          role === "OWNER" &&
          !organizationSetupCompleted &&
          item.href !== "/dashboard";

        const desktopCollapsed = !mobile && collapsed;

        const content = (
          <>
            <Icon
              aria-hidden="true"
              className={cn(
                "shrink-0",
                desktopCollapsed ? "size-[21px]" : "size-5",
              )}
            />

            {!desktopCollapsed ? (
              <span>{item.label}</span>
            ) : null}

            {locked ? (
              <LockKeyhole
                aria-hidden="true"
                className={cn(
                  "size-3.5",
                  !mobile &&
                    !collapsed &&
                    "ml-auto",
                  desktopCollapsed &&
                    "absolute right-1.5 top-1.5 size-2.5",
                )}
              />
            ) : null}

            {!mobile && locked ? (
              <span className="sr-only">
                Bloqueado
              </span>
            ) : null}
          </>
        );

        if (locked) {
          return (
            <span
              aria-disabled="true"
              className={cn(
                "relative flex cursor-not-allowed items-center opacity-55",
                mobile
                  ? "min-h-16 flex-col justify-center gap-1 px-1 text-[10px] font-semibold text-muted"
                  : collapsed
                    ? "mx-auto size-12 justify-center rounded-xl text-app-sidebar-muted"
                    : "min-h-11 gap-3 rounded-lg px-3 text-sm font-semibold text-app-sidebar-muted",
              )}
              key={item.href}
              title={
                collapsed
                  ? `${item.label} · Completá la configuración inicial para habilitar esta función.`
                  : "Completá la configuración inicial para habilitar esta función."
              }
            >
              {content}
            </span>
          );
        }

        return (
          <Link
            aria-current={active ? "page" : undefined}
            aria-label={
              desktopCollapsed ? item.label : undefined
            }
            className={cn(
              "group relative flex items-center transition-[background-color,color,border-color] duration-150",
              mobile
                ? "min-h-16 flex-col justify-center gap-1 px-1 text-[10px] font-semibold"
                : collapsed
                  ? "mx-auto size-12 justify-center rounded-xl border border-transparent"
                  : "min-h-11 gap-3 rounded-lg px-3 text-sm font-semibold",
              active
                ? mobile
                  ? "text-accent"
                  : collapsed
                    ? "border-app-border bg-app-sidebar-active text-app-sidebar-text"
                    : "bg-app-sidebar-active text-app-sidebar-text"
                : mobile
                  ? "text-muted hover:bg-surface-hover hover:text-primary"
                  : "text-app-sidebar-muted hover:bg-app-sidebar-hover hover:text-app-sidebar-text",
            )}
            href={item.href}
            key={item.href}
            title={desktopCollapsed ? item.label : undefined}
          >
            {content}

            {desktopCollapsed && active ? (
              <span
                aria-hidden="true"
                className="absolute -left-2 top-1/2 h-6 w-[3px] -translate-y-1/2 rounded-r-full bg-accent"
              />
            ) : null}
          </Link>
        );
      })}
    </nav>
  );
}
