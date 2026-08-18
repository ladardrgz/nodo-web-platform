import type { ReactNode } from "react";

import { SuperadminShell } from "@/components/layout/SuperadminShell";
import { requireRole } from "@/lib/auth/session";

export default async function SuperadminLayout({ children }: { children: ReactNode }) {
  const context = await requireRole(["SUPERADMIN"]);
  return <SuperadminShell context={context}>{children}</SuperadminShell>;
}
