"use client";

import { useState, type ReactNode } from "react";

import { AppLogo } from "@/components/branding/AppLogo";
import { AdminNavigation } from "@/components/layout/AdminNavigation";
import { AppSidebar } from "@/components/layout/AppSidebar";
import { ThemeToggle } from "@/components/ui/ThemeToggle";
import { cn } from "@/lib/cn";
import type { AuthContext } from "@/types/auth";

export function SuperadminShell({ children, context }: { children: ReactNode; context: AuthContext }) {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  return (
    <div className="app-shell app-background min-h-screen">
      <AppSidebar
        collapsed={sidebarCollapsed}
        context={context}
        onToggleCollapsed={() => setSidebarCollapsed((current) => !current)}
        organizationSetupCompleted
      />

      <div className={cn("min-h-screen transition-[padding-left] duration-300 ease-out", sidebarCollapsed ? "lg:pl-[76px]" : "lg:pl-60")}>
        <header className="sticky top-0 z-30 border-b border-app-border bg-app-surface/95 backdrop-blur lg:hidden">
          <div className="flex min-h-16 items-center justify-between gap-3 px-4">
            <AppLogo compact className="text-primary" />
            <ThemeToggle />
          </div>
          <AdminNavigation mobile organizationSetupCompleted role="SUPERADMIN" />
        </header>
        <main className="mx-auto w-full max-w-[1500px] px-4 py-6 pb-24 sm:px-6 lg:px-8 lg:py-8">{children}</main>
      </div>
    </div>
  );
}
