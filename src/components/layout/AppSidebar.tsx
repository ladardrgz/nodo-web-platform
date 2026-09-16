"use client";

import {
  PanelLeftClose,
  PanelLeftOpen,
  Settings,
} from "lucide-react";
import Link from "next/link";

import { AppLogo } from "@/components/branding/AppLogo";
import { AdminNavigation } from "@/components/layout/AdminNavigation";
import { getRoleDashboardHref, getRoleNavigationLabel } from "@/config/navigation";
import { logoutAction } from "@/features/auth/actions";
import { LogoutSubmitButton } from "@/features/auth/components/LogoutSubmitButton";
import { cn } from "@/lib/cn";
import type { AuthContext } from "@/types/auth";

interface AppSidebarProps {
  context: AuthContext;
  organizationSetupCompleted: boolean;
  collapsed: boolean;
  onToggleCollapsed: () => void;
}

export function AppSidebar({
  context,
  organizationSetupCompleted,
  collapsed,
  onToggleCollapsed,
}: AppSidebarProps) {
  const fullName =
    context.profile.display_name ||
    [context.profile.first_name, context.profile.last_name]
      .filter(Boolean)
      .join(" ") ||
    context.email ||
    "Usuario";

  const shortName =
    context.profile.first_name?.trim() ||
    context.profile.display_name?.trim().split(/\s+/).slice(0, 2).join(" ") ||
    context.email?.split("@")[0] ||
    "Usuario";

  const initials = fullName
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();

  const settingsHref = organizationSetupCompleted
    ? context.profile.role === "SUPERADMIN" ? "/superadmin/profile" : "/organization-settings"
    : "/initial-setup";

  const settingsLabel = context.profile.role === "SUPERADMIN"
    ? "Mi perfil"
    : organizationSetupCompleted ? "Ajustes" : "Primeros pasos";

  const roleLabel = context.profile.role === "SUPERADMIN"
    ? "Superadministrador"
    : context.profile.role === "CUSTOMER" ? "Cliente" : "Propietario";
  const dashboardHref = getRoleDashboardHref(context.profile.role);
  const showSettings = context.profile.role !== "CUSTOMER";

  return (
    <aside
      className={cn(
        "fixed inset-y-0 left-0 z-40 hidden flex-col overflow-hidden border-r border-app-border bg-app-sidebar text-app-sidebar-text transition-[width] duration-300 ease-out lg:flex",
        collapsed ? "w-[76px]" : "w-60",
      )}
    >
      {/* Marca + control de minimización */}
      <div
        className={cn(
          "flex min-h-20 shrink-0 items-center border-b border-app-border",
          collapsed
            ? "justify-center px-2"
            : "justify-between gap-3 px-4",
        )}
      >
        <Link
          aria-label="Ir al dashboard"
          className="min-w-0 flex-1"
          href={dashboardHref}
          title={collapsed ? "Nodo" : undefined}
        >
          <AppLogo
            className="text-app-sidebar-text"
            compact
            iconOnly={collapsed}
            showSubtitle={false}
          />
        </Link>

        {!collapsed ? (
          <button
            aria-label="Minimizar menú lateral"
            className="grid size-9 shrink-0 place-items-center rounded-lg text-app-sidebar-muted transition-colors hover:bg-app-sidebar-hover hover:text-app-sidebar-text focus-visible:outline-2 focus-visible:outline-accent"
            onClick={onToggleCollapsed}
            title="Minimizar menú"
            type="button"
          >
            <PanelLeftClose
              aria-hidden="true"
              className="size-[18px]"
            />
          </button>
        ) : null}
      </div>

      {/* Navegación */}
      <div
        className={cn(
          "min-h-0 flex-1 overflow-y-auto py-5",
          collapsed ? "px-2" : "px-3",
        )}
      >
        {!collapsed ? (
          <p className="mb-3 px-3 text-[11px] font-bold uppercase tracking-[0.18em] text-app-sidebar-muted">
            {getRoleNavigationLabel(context.profile.role)}
          </p>
        ) : (
          <div
            aria-hidden="true"
            className="mx-auto mb-4 h-px w-8 bg-app-border"
          />
        )}

        <AdminNavigation
          collapsed={collapsed}
          organizationSetupCompleted={organizationSetupCompleted}
          role={context.profile.role}
        />
      </div>

      {/* Zona inferior */}
      <div
        className={cn(
          "shrink-0 border-t border-app-border",
          collapsed ? "px-2 py-3" : "px-4 py-4",
        )}
      >
        {/* Perfil */}
        <div
          className={cn(
            "flex items-center",
            collapsed
              ? "mb-3 justify-center"
              : "mb-4 gap-3",
          )}
          title={collapsed ? `${fullName} · ${roleLabel}` : undefined}
        >
          <span className="grid size-10 shrink-0 place-items-center rounded-full bg-accent-button text-xs font-bold text-white shadow-sm">
            {initials}
          </span>

          {!collapsed ? (
            <div className="min-w-0 flex-1">
              <strong
                className="block truncate text-sm font-semibold leading-5 text-app-sidebar-text"
                title={fullName}
              >
                {shortName}
              </strong>

              <span className="block text-xs leading-4 text-app-sidebar-muted">
                {roleLabel}
              </span>
            </div>
          ) : null}
        </div>

        {/* Acciones */}
        <div
          className={cn(
            "border-t border-app-border pt-3",
            collapsed
              ? "flex flex-col gap-1.5"
              : showSettings ? "grid grid-cols-2 gap-2" : "grid gap-2",
          )}
        >
          {showSettings ? <Link
            aria-label={settingsLabel}
            className={cn(
                "flex min-h-10 items-center rounded-lg font-semibold text-app-sidebar-muted transition-colors hover:bg-app-sidebar-hover hover:text-app-sidebar-text",
              collapsed
                ? "justify-center px-0"
                : "justify-center gap-2 px-2 text-xs",
            )}
            href={settingsHref}
            title={collapsed ? settingsLabel : undefined}
          >
            <Settings
              aria-hidden="true"
              className="size-[18px]"
            />

            {!collapsed ? (
              <span>{settingsLabel}</span>
            ) : null}
          </Link> : null}

          <form action={logoutAction}>
            <LogoutSubmitButton
              className={cn(
                "min-h-10 w-full rounded-lg text-app-sidebar-muted transition-colors hover:bg-app-sidebar-hover hover:text-app-sidebar-text",
                collapsed
                  ? "px-0"
                  : "text-xs font-semibold",
              )}
              compact={collapsed}
              label="Salir"
            />
          </form>
        </div>

        {/* Restaurar sidebar */}
        {collapsed ? (
          <button
            aria-label="Expandir menú lateral"
            className="mt-2 grid min-h-10 w-full place-items-center rounded-lg border border-app-border text-app-sidebar-muted transition-colors hover:border-line-strong hover:bg-app-sidebar-hover hover:text-app-sidebar-text focus-visible:outline-2 focus-visible:outline-accent"
            onClick={onToggleCollapsed}
            title="Expandir menú"
            type="button"
          >
            <PanelLeftOpen
              aria-hidden="true"
              className="size-[18px]"
            />
          </button>
        ) : null}
      </div>
    </aside>
  );
}
