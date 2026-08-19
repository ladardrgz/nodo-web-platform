import { afterEach, describe, expect, it } from "vitest";

import { forgotPasswordSchema, loginSchema, passwordChangeSchema, registerSchema } from "../src/features/auth/schemas";
import { canAccessBackoffice, canAccessCustomerPortal, canAccessSuperadmin } from "../src/lib/auth/permissions";
import { isGoogleAuthEnabled } from "../src/lib/auth/features";
import { getLegacyRecoveryRedirect } from "../src/lib/auth/legacy-recovery";
import { mapAuthError } from "../src/lib/auth/messages";
import { roleCanAccessPath, roleDestination, sanitizeInternalRedirect, withAuthFeedback } from "../src/lib/auth/redirects";
import { getClientIp } from "../src/lib/security/client-ip";
import { createRateLimitKey } from "../src/lib/security/rate-limit-key";
import { getAppUrl } from "../src/lib/supabase/app-url";
import { normalizeSupabaseUrl } from "../src/lib/supabase/supabase-url";

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

  it("rescata enlaces recovery antiguos que llegaron por error al Home", () => {
    const destination = getLegacyRecoveryRedirect(new URL("https://nodo.example/?code=auth-code"));
    expect(destination?.toString()).toBe("https://nodo.example/auth/confirm?code=auth-code");
    expect(getLegacyRecoveryRedirect(new URL("https://nodo.example/?q=normal"))).toBeNull();
    expect(getLegacyRecoveryRedirect(new URL("https://nodo.example/login?code=auth-code"))).toBeNull();
  });
});

describe("URL canónica de autenticación", () => {
  const originalSiteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  const originalAppUrl = process.env.APP_URL;
  const originalProductionUrl = process.env.VERCEL_PROJECT_PRODUCTION_URL;
  const originalVercelUrl = process.env.VERCEL_URL;

  afterEach(() => {
    if (originalSiteUrl === undefined) delete process.env.NEXT_PUBLIC_SITE_URL; else process.env.NEXT_PUBLIC_SITE_URL = originalSiteUrl;
    if (originalAppUrl === undefined) delete process.env.APP_URL; else process.env.APP_URL = originalAppUrl;
    if (originalProductionUrl === undefined) delete process.env.VERCEL_PROJECT_PRODUCTION_URL; else process.env.VERCEL_PROJECT_PRODUCTION_URL = originalProductionUrl;
    if (originalVercelUrl === undefined) delete process.env.VERCEL_URL; else process.env.VERCEL_URL = originalVercelUrl;
  });

  it("prioriza NEXT_PUBLIC_SITE_URL sobre dominios temporales de Vercel", () => {
    process.env.NEXT_PUBLIC_SITE_URL = "https://nodo-web-platform.vercel.app/";
    process.env.APP_URL = "http://localhost:3000";
    process.env.VERCEL_URL = "nodo-temporal.vercel.app";
    expect(getAppUrl()).toBe("https://nodo-web-platform.vercel.app");
  });

  it("usa la URL estable del proyecto antes del deployment temporal", () => {
    delete process.env.NEXT_PUBLIC_SITE_URL;
    process.env.APP_URL = "http://localhost:3000";
    process.env.VERCEL_PROJECT_PRODUCTION_URL = "nodo-web-platform.vercel.app";
    process.env.VERCEL_URL = "nodo-temporal.vercel.app";
    expect(getAppUrl()).toBe("https://nodo-web-platform.vercel.app");
  });
});

describe("configuración pública de Supabase", () => {
  it("normaliza URLs que incluyan accidentalmente un endpoint de la API", () => {
    expect(normalizeSupabaseUrl("https://project.supabase.co/rest/v1")).toBe("https://project.supabase.co");
    expect(normalizeSupabaseUrl("https://project.supabase.co/auth/v1/")).toBe("https://project.supabase.co");
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

describe("mensajes de autenticación", () => {
  it("traduce errores conocidos sin exponer texto técnico", () => {
    expect(mapAuthError({ message: "Invalid login credentials" }, "login")).toEqual({ variant: "error", title: "No pudimos iniciar sesión", description: "El correo o la contraseña no son correctos." });
    expect(mapAuthError({ message: "User already registered" }, "register")).toEqual({ variant: "error", title: "Correo ya registrado", description: "Ya existe una cuenta asociada a esta dirección." });
    expect(mapAuthError({ message: "Token has expired" }, "recovery")).toEqual({ variant: "error", title: "El enlace venció", description: "Solicitá un nuevo enlace para continuar." });
  });

  it("usa un fallback seguro para errores desconocidos", () => {
    expect(mapAuthError({ message: "internal database failure" }, "password")).toEqual({ variant: "error", title: "No pudimos actualizar la contraseña", description: "Intentá nuevamente en unos minutos." });
  });

  it("distingue conexión, rate limit e invitaciones pendientes", () => {
    expect(mapAuthError(new TypeError("Failed to fetch"), "login").title).toBe("No pudimos conectarnos");
    expect(mapAuthError({ message: "Email rate limit exceeded" }, "recovery").title).toBe("Demasiados intentos");
    expect(mapAuthError({ message: "Invitation already pending" }, "invite").title).toBe("Invitación pendiente");
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
