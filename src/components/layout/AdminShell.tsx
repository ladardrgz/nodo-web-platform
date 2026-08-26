import type { ReactNode } from "react";

import { AppHeader } from "@/components/layout/AppHeader";
import { AppSidebar } from "@/components/layout/AppSidebar";
import { MobileNavigation } from "@/components/layout/MobileNavigation";
import type { QuickLinkItem } from "@/features/quick-links/config";
import type { AuthContext } from "@/types/auth";

export function AdminShell({ children, context, organizationSetupCompleted, quickLinks }: { children: ReactNode; context: AuthContext; organizationSetupCompleted: boolean; quickLinks: QuickLinkItem[] }) {
  return (
    <div className="app-shell owner-shell owner-app-background min-h-screen">
      <AppSidebar context={context} organizationSetupCompleted={organizationSetupCompleted} />
      <div className="min-h-screen lg:pl-72">
        <AppHeader organizationSetupCompleted={organizationSetupCompleted} quickLinks={quickLinks} />
        <main className="mx-auto w-full max-w-[1600px] px-4 py-6 pb-24 sm:px-6 lg:px-8 lg:py-8 lg:pb-8">
          {children}
        </main>
      </div>
      <MobileNavigation organizationSetupCompleted={organizationSetupCompleted} />
    </div>
  );
}
