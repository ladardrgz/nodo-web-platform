import type { AppRole } from "@/types/auth";

export function organizationAllowsOperationalAccess(role: AppRole, organizationStatus: string | null | undefined): boolean {
  return role === "SUPERADMIN" || organizationStatus === "ACTIVE";
}
