import { AdminNavigation } from "@/components/layout/AdminNavigation";
import type { AppRole } from "@/types/auth";

export function MobileNavigation({ organizationSetupCompleted, role }: { organizationSetupCompleted: boolean; role: AppRole }) {
  return (
    <div className="fixed inset-x-0 bottom-0 z-40 border-t border-app-border bg-app-surface/98 pb-[env(safe-area-inset-bottom)] shadow-[0_-8px_30px_rgb(var(--shadow-color)/12%)] lg:hidden">
      <AdminNavigation mobile organizationSetupCompleted={organizationSetupCompleted} role={role} />
    </div>
  );
}
