"use client";

import { useState, type ReactNode } from "react";

import { AppHeader } from "@/components/layout/AppHeader";
import { AppSidebar } from "@/components/layout/AppSidebar";
import { MobileNavigation } from "@/components/layout/MobileNavigation";
import type { QuickLinkItem } from "@/features/quick-links/config";
import { cn } from "@/lib/cn";
import type { AuthContext } from "@/types/auth";

interface AdminShellProps {
  children: ReactNode;
  context: AuthContext;
  organizationSetupCompleted: boolean;
  quickLinks: QuickLinkItem[];
}

export function AdminShell({
  children,
  context,
  organizationSetupCompleted,
  quickLinks,
}: AdminShellProps) {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  return (
    <div className="app-shell owner-shell owner-app-background min-h-screen">
      <AppSidebar
        collapsed={sidebarCollapsed}
        context={context}
        onToggleCollapsed={() => setSidebarCollapsed((current) => !current)}
        organizationSetupCompleted={organizationSetupCompleted}
      />

      <div
        className={cn(
          "min-h-screen transition-[padding-left] duration-300 ease-out",
          sidebarCollapsed ? "lg:pl-[76px]" : "lg:pl-60",
        )}
      >
        <AppHeader
          organizationSetupCompleted={organizationSetupCompleted}
          quickLinks={quickLinks}
        />

        <main className="mx-auto w-full max-w-[1600px] px-4 py-6 pb-24 sm:px-6 lg:px-8 lg:py-8 lg:pb-8">
          {children}
        </main>
      </div>

      <MobileNavigation
        organizationSetupCompleted={organizationSetupCompleted}
        role={context.profile.role}
      />
    </div>
  );
}
