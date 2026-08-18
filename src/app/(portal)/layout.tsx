import type { ReactNode } from "react";

import { requireRole } from "@/lib/auth/session";

export default async function PortalLayout({ children }: { children: ReactNode }) {
  await requireRole(["CUSTOMER"]);
  return children;
}
