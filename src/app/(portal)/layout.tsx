import type { ReactNode } from "react";

import { CustomerShell } from "@/components/layout/CustomerShell";
import { requireRole } from "@/lib/auth/session";

export default async function PortalLayout({ children }: { children: ReactNode }) {
  const context = await requireRole(["CUSTOMER"]);
  return <CustomerShell context={context}>{children}</CustomerShell>;
}
