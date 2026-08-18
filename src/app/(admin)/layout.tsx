import type { ReactNode } from "react";

import { AdminShell } from "@/components/layout/AdminShell";
import { requireRole } from "@/lib/auth/session";

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const context = await requireRole(["OWNER"]);
  return <AdminShell context={context}>{children}</AdminShell>;
}
