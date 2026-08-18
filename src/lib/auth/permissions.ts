import type { AppRole } from "@/types/auth";

export function hasRole(role: AppRole, allowedRoles: readonly AppRole[]): boolean {
  return allowedRoles.includes(role);
}

export function canAccessBackoffice(role: AppRole): boolean {
  return role === "OWNER";
}

export function canAccessSuperadmin(role: AppRole): boolean {
  return role === "SUPERADMIN";
}

export function canAccessCustomerPortal(role: AppRole): boolean {
  return role === "CUSTOMER";
}
