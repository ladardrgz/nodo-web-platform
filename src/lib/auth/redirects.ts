import type { AppRole } from "@/types/auth";

const DEFAULT_DESTINATION = "/login";

export function sanitizeInternalRedirect(value: string | null | undefined): string | null {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) {
    return null;
  }

  try {
    const url = new URL(value, "https://nodo.invalid");
    return url.origin === "https://nodo.invalid" ? `${url.pathname}${url.search}${url.hash}` : null;
  } catch {
    return null;
  }
}

export function roleDestination(role: AppRole, mustChangePassword = false): string {
  if (mustChangePassword) return "/change-password";

  switch (role) {
    case "SUPERADMIN":
      return "/superadmin";
    case "OWNER":
      return "/dashboard";
    case "CUSTOMER":
      return "/portal";
    case "TECHNICIAN":
      return "/forbidden";
    default:
      return DEFAULT_DESTINATION;
  }
}

export function roleCanAccessPath(role: AppRole, path: string): boolean {
  let pathname: string;
  try {
    pathname = new URL(path, "https://nodo.invalid").pathname;
  } catch {
    return false;
  }

  if (role === "SUPERADMIN") return pathname === "/superadmin" || pathname.startsWith("/superadmin/");
  if (role === "CUSTOMER") return pathname === "/portal" || pathname.startsWith("/portal/");
  if (role === "OWNER") {
    return ["/dashboard", "/repairs", "/customers", "/inventory", "/prices"].some(
      (root) => pathname === root || pathname.startsWith(`${root}/`),
    );
  }
  return false;
}

export function withAuthFeedback(path: string, feedback: "session_started" | "account_created" | "password_changed" | "signed_out"): string {
  const url = new URL(path, "https://nodo.invalid");
  url.searchParams.set("auth", feedback);
  return `${url.pathname}${url.search}${url.hash}`;
}
