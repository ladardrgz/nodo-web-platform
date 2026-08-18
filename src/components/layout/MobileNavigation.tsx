import { AdminNavigation } from "@/components/layout/AdminNavigation";

export function MobileNavigation() {
  return (
    <div className="fixed inset-x-0 bottom-0 z-40 border-t border-app-border bg-app-surface/98 pb-[env(safe-area-inset-bottom)] shadow-[0_-8px_30px_rgba(15,23,42,0.08)] lg:hidden">
      <AdminNavigation mobile />
    </div>
  );
}
