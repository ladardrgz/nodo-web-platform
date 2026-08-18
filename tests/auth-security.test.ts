import { afterEach, describe, expect, it } from "vitest";

import { forgotPasswordSchema, loginSchema, passwordChangeSchema, registerSchema } from "../src/features/auth/schemas";
import { canAccessBackoffice, canAccessCustomerPortal, canAccessSuperadmin } from "../src/lib/auth/permissions";
import { isGoogleAuthEnabled } from "../src/lib/auth/features";
import { roleCanAccessPath, roleDestination, sanitizeInternalRedirect, withAuthFeedback } from "../src/lib/auth/redirects";
import { getClientIp } from "../src/lib/security/client-ip";
import { createRateLimitKey } from "../src/lib/security/rate-limit-key";

describe("redirecciones de autenticación", () => {
  it("acepta sólo rutas internas y evita open redirects", () => {
    expect(sanitizeInternalRedirect("/repairs?q=demo")).toBe("/repairs?q=demo");
    expect(sanitizeInternalRedirect("https://evil.example/path")).toBeNull();
    expect(sanitizeInternalRedirect("//evil.example/path")).toBeNull();
    expect(sanitizeInternalRedirect("/safe\\evil")).toBeNull();
  });

  it("separa destinos y rutas por rol", () => {
    expect(roleDestination("SUPERADMIN")).toBe("/superadmin");
    expect(roleDestination("OWNER")).toBe("/dashboard");
    expect(roleDestination("CUSTOMER")).toBe("/portal");
    expect(roleCanAccessPath("CUSTOMER", "/dashboard")).toBe(false);
    expect(roleCanAccessPath("OWNER", "/repairs/demo")).toBe(true);
    expect(roleCanAccessPath("OWNER", "/repairs?q=pending")).toBe(true);
  });

  it("agrega feedback de sesión sin perder la ruta ni sus parámetros", () => {
    expect(withAuthFeedback("/portal?tab=repairs#latest", "session_started")).toBe(
      "/portal?tab=repairs&auth=session_started#latest",
    );
  });
});

describe("validación y autorización", () => {
  it("rechaza contraseñas débiles", () => {
    const result = registerSchema.safeParse({ firstName: "Ana", lastName: "Paz", email: "ana@example.test", password: "debil", confirmPassword: "debil", role: "SUPERADMIN" });
    expect(result.success).toBe(false);
  });

  it("no acepta un rol desde el registro público", () => {
    const result = registerSchema.parse({ firstName: "Ana", lastName: "Paz", email: "ana@example.test", password: "Clave-Segura-2026", confirmPassword: "Clave-Segura-2026", role: "SUPERADMIN" });
    expect("role" in result).toBe(false);
    expect(loginSchema.safeParse({ email: "no-es-email", password: "x" }).success).toBe(false);
  });

  it("devuelve mensajes específicos para campos vacíos o correo inválido", () => {
    const empty = loginSchema.safeParse({ email: "", password: "" });
    expect(empty.success).toBe(false);
    if (!empty.success) {
      expect(empty.error.flatten().fieldErrors.email?.[0]).toBe("Ingresá tu correo electrónico.");
      expect(empty.error.flatten().fieldErrors.password?.[0]).toBe("Ingresá tu contraseña.");
    }

    const invalid = loginSchema.safeParse({ email: "correo-invalido", password: "secreto" });
    expect(invalid.success).toBe(false);
    if (!invalid.success) {
      expect(invalid.error.flatten().fieldErrors.email?.[0]).toBe(
        "El correo electrónico no tiene un formato válido.",
      );
    }
  });

  it("mantiene permisos mutuamente separados", () => {
    expect(canAccessSuperadmin("SUPERADMIN")).toBe(true);
    expect(canAccessSuperadmin("OWNER")).toBe(false);
    expect(canAccessBackoffice("OWNER")).toBe(true);
    expect(canAccessCustomerPortal("CUSTOMER")).toBe(true);
  });

  it("valida recuperación y cambio de contraseña con los mismos esquemas del servidor", () => {
    expect(forgotPasswordSchema.safeParse({ email: "correo-invalido" }).success).toBe(false);
    expect(passwordChangeSchema.safeParse({ password: "Clave-Segura-2026!", confirmPassword: "otra" }).success).toBe(false);
  });
});

describe("Google OAuth opcional", () => {
  const originalValue = process.env.ENABLE_GOOGLE_AUTH;
  afterEach(() => {
    if (originalValue === undefined) delete process.env.ENABLE_GOOGLE_AUTH;
    else process.env.ENABLE_GOOGLE_AUTH = originalValue;
  });

  it("permanece desactivado salvo habilitación explícita", () => {
    delete process.env.ENABLE_GOOGLE_AUTH;
    expect(isGoogleAuthEnabled()).toBe(false);
    process.env.ENABLE_GOOGLE_AUTH = "false";
    expect(isGoogleAuthEnabled()).toBe(false);
    process.env.ENABLE_GOOGLE_AUTH = "true";
    expect(isGoogleAuthEnabled()).toBe(true);
  });
});

describe("protecciones del rate limit", () => {
  const originalProvider = process.env.TRUSTED_PROXY_PROVIDER;
  afterEach(() => { process.env.TRUSTED_PROXY_PROVIDER = originalProvider; });

  it("no confía en X-Forwarded-For sin un proxy declarado", () => {
    process.env.TRUSTED_PROXY_PROVIDER = "none";
    expect(getClientIp({ get: () => "203.0.113.10" })).toBeNull();
  });

  it("acepta la IP únicamente con el proveedor configurado", () => {
    process.env.TRUSTED_PROXY_PROVIDER = "single-proxy";
    expect(getClientIp({ get: (name) => name === "x-forwarded-for" ? "203.0.113.10, 10.0.0.1" : null })).toBe("203.0.113.10");
  });

  it("genera claves HMAC normalizadas sin guardar el identificador", () => {
    const key = createRateLimitKey("a".repeat(32), "LOGIN", "identifier", "User@Example.Test ");
    expect(key).toMatch(/^[a-f0-9]{64}$/);
    expect(key).not.toContain("user@example.test");
    expect(key).toBe(createRateLimitKey("a".repeat(32), "LOGIN", "identifier", "user@example.test"));
  });
});
