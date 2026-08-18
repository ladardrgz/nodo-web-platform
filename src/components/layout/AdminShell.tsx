import type { ReactNode } from "react";

import { AppHeader } from "@/components/layout/AppHeader";
import { AppSidebar } from "@/components/layout/AppSidebar";
import { MobileNavigation } from "@/components/layout/MobileNavigation";
import type { AuthContext } from "@/types/auth";

export function AdminShell({ children, context }: { children: ReactNode; context: AuthContext }) {
  return (
    <div className="app-shell app-background min-h-screen">
      <AppSidebar context={context} />
      <div className="min-h-screen lg:pl-72">
        <AppHeader context={context} />
        <main className="mx-auto w-full max-w-[1600px] px-4 py-6 pb-24 sm:px-6 lg:px-8 lg:py-8 lg:pb-8">
          {children}
        </main>
      </div>
      <MobileNavigation />
    </div>
  );
}
