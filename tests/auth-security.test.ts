import { afterEach, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { forgotPasswordSchema, loginSchema, passwordChangeSchema, registerSchema } from "../src/features/auth/schemas";
import { canAccessBackoffice, canAccessCustomerPortal, canAccessSuperadmin } from "../src/lib/auth/permissions";
import { isGoogleAuthEnabled } from "../src/lib/auth/features";
import { getLegacyRecoveryRedirect } from "../src/lib/auth/legacy-recovery";
import { organizationAllowsOperationalAccess } from "../src/lib/auth/organization-access";
import { mapAuthError } from "../src/lib/auth/messages";
import { roleCanAccessPath, roleDestination, sanitizeInternalRedirect, withAuthFeedback } from "../src/lib/auth/redirects";
import { getClientIp } from "../src/lib/security/client-ip";
import { createRateLimitKey } from "../src/lib/security/rate-limit-key";
import {
  ORGANIZATION_LOGO_MAX_BYTES,
  normalizeContactPhone,
  organizationSetupSchema,
  organizationStepOneSchema,
  organizationStepThreeSchema,
  organizationStepTwoSchema,
  validateOrganizationLogo,
} from "../src/features/organizations/schemas";
import { canSelectSetupStep, highestUnlockedSetupStep } from "../src/features/organizations/setup-wizard-state";
import { selectLocality, selectProvince } from "../src/features/organizations/location-state";
import { formatAddress } from "../src/lib/organizations/address";
import { getOrganizationDisplayName } from "../src/lib/organizations/display-name";
import {
  normalizeOrganizationName,
  normalizeOrganizationNameForComparison,
  organizationNameSchema,
  organizationSlugSchema,
} from "../src/features/superadmin/organization-schema";
import { pageRange, paginate } from "../src/features/superadmin/list-utils";
import { superadminPasswordSchema, superadminProfileSchema } from "../src/features/superadmin/profile-schema";
import { inviteUserSchema, normalizePersonName, requiredRoleConfirmation } from "../src/features/superadmin/user-schema";
import { validateQuickLinkUrl } from "../src/features/quick-links/validation";
import { argentinaGreeting, formatArgentinaDateTime, formatArgentinaLongDate } from "../src/lib/argentina-time";
import { ownerActivityLabel } from "../src/features/dashboard/activity-labels";
import {
  addCivilDays,
  agendaWindowRange,
  argentinaDateKey,
  buildCalendarMonth,
  formatCalendarAriaLabel,
  formatMonthLabel,
  shiftCalendarMonth,
} from "../src/features/dashboard/agenda/date-utils";
import { groupAgendaEvents } from "../src/features/dashboard/agenda/event-utils";
import { AGENDA_EVENT_TYPES, type AgendaEvent } from "../src/features/dashboard/agenda/types";
import { weatherConditionFromCode } from "../src/features/dashboard/weather/conditions";
import {
  buildOpenMeteoForecastUrl,
  buildOpenMeteoGeocodingUrl,
  mapOpenMeteoForecast,
  resolveOpenMeteoCoordinates,
} from "../src/features/dashboard/weather/open-meteo-mapper";
import type { WeatherLocation } from "../src/features/dashboard/weather/types";
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
    expect(roleCanAccessPath("OWNER", "/initial-setup")).toBe(true);
    expect(roleCanAccessPath("OWNER", "/organization-settings")).toBe(true);
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

describe("configuración inicial de organizaciones", () => {
  it("mantiene un único estado persistente y redirige rutas operativas al onboarding", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190001_owner_initial_setup.sql"), "utf8");
    const setupGuard = readFileSync(join(process.cwd(), "src/lib/organizations/setup.ts"), "utf8");
    expect(migration).toContain("initial_setup_completed");
    expect(migration).toContain("alter column initial_setup_completed set default false");
    expect(setupGuard).toContain('redirect("/initial-setup")');
  });

  it("protege las rutas operativas y permite únicamente bienvenida y configuración inicial", () => {
    for (const page of [
      "src/app/(admin)/repairs/page.tsx",
      "src/app/(admin)/repairs/new/page.tsx",
      "src/app/(admin)/customers/page.tsx",
      "src/app/(admin)/inventory/page.tsx",
      "src/app/(admin)/prices/page.tsx",
    ]) {
      expect(readFileSync(join(process.cwd(), page), "utf8")).toContain("requireOwnerOrganization()");
    }

    const initialSetupPage = readFileSync(join(process.cwd(), "src/app/(admin)/initial-setup/page.tsx"), "utf8");
    const settingsPage = readFileSync(join(process.cwd(), "src/app/(admin)/organization-settings/page.tsx"), "utf8");
    const settingsAction = readFileSync(join(process.cwd(), "src/features/organizations/actions.ts"), "utf8");
    expect(initialSetupPage).toContain("allowIncompleteSetup: true");
    expect(initialSetupPage).not.toContain("OrganizationSettingsForm");
    expect(settingsPage).toContain('redirect("/initial-setup")');
    expect(settingsAction).toContain("requireOwnerOrganization()");
  });

  it("reutiliza el saludo de Argentina y dirige el CTA al flujo preparado", () => {
    const welcome = readFileSync(join(process.cwd(), "src/features/organizations/components/OwnerSetupWelcome.tsx"), "utf8");
    expect(welcome).toContain("argentinaGreeting");
    expect(welcome).toContain('href="/initial-setup"');
    expect(welcome).toContain("Entendido, continuar");
    expect(welcome).not.toContain("getHours()");
  });

  it("no permite saltar pasos obligatorios y habilita el siguiente en secuencia", () => {
    expect(highestUnlockedSetupStep(new Set(), 4)).toBe(0);
    expect(canSelectSetupStep(2, new Set(), 4)).toBe(false);
    expect(canSelectSetupStep(1, new Set([0]), 4)).toBe(true);
    expect(canSelectSetupStep(2, new Set([0]), 4)).toBe(false);
    expect(canSelectSetupStep(2, new Set([0, 1]), 4)).toBe(true);
  });

  it("valida y normaliza los nombres reales del Paso 1", () => {
    expect(organizationStepOneSchema.parse({
      legalName: "  R&R   Asociados S.R.L. ",
      commercialName: "  R&R  ",
    })).toEqual({ legalName: "R&R Asociados S.R.L.", commercialName: "R&R" });

    expect(organizationStepOneSchema.parse({
      legalName: "Electrónica Formosa S.A.",
      commercialName: "Servicio Móvil",
    })).toEqual({ legalName: "Electrónica Formosa S.A.", commercialName: "Servicio Móvil" });

    for (const values of [
      { legalName: "", commercialName: "R&R" },
      { legalName: "R&R Asociados", commercialName: "" },
      { legalName: " ", commercialName: "FixTech" },
      { legalName: "A", commercialName: "F" },
    ]) {
      expect(organizationStepOneSchema.safeParse(values).success).toBe(false);
    }
  });

  it("acepta logos PNG, JPG y WebP y rechaza SVG, archivos no imagen y tamaños excesivos", () => {
    for (const type of ["image/png", "image/jpeg", "image/webp"]) {
      expect(validateOrganizationLogo({ type, size: 128_000 })).toBeNull();
    }
    expect(validateOrganizationLogo({ type: "image/svg+xml", size: 10_000 })).toContain("no es compatible");
    expect(validateOrganizationLogo({ type: "text/plain", size: 10_000 })).toContain("no es compatible");
    expect(validateOrganizationLogo({ type: "image/png", size: ORGANIZATION_LOGO_MAX_BYTES + 1 })).toContain("2 MB");
  });

  it("persiste solamente el Paso 1 para la organización autenticada", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190005_owner_setup_step_one.sql"), "utf8");
    expect(migration).toContain("initial_setup_step = greatest(initial_setup_step, 2)");
    expect(migration).toContain("initial_setup_completed = false");
    expect(migration).toContain("public.current_organization_id()");
    expect(migration).toContain("public.current_app_role() <> 'OWNER'");
    expect(migration).toContain("v_organization_id::text || '/logo/%'");
    expect(migration).not.toContain("initial_setup_completed = true");
  });

  it("valida y normaliza teléfono y email del Paso 2", () => {
    expect(organizationStepTwoSchema.parse({
      phone: "+54 3705 234524",
      contactEmail: "  CONTACTO@TALLER.COM.AR ",
    })).toEqual({ phone: "+543705234524", contactEmail: "contacto@taller.com.ar" });
    expect(normalizeContactPhone("+54 3705 234524")).toBe("+543705234524");

    for (const values of [
      { phone: "", contactEmail: "contacto@taller.com.ar" },
      { phone: "+5412", contactEmail: "contacto@taller.com.ar" },
      { phone: "teléfono", contactEmail: "contacto@taller.com.ar" },
      { phone: "+543705234524", contactEmail: "" },
      { phone: "+543705234524", contactEmail: "contacto" },
      { phone: "+543705234524", contactEmail: "contacto@" },
      { phone: "+543705234524", contactEmail: "contacto @taller.com" },
    ]) {
      expect(organizationStepTwoSchema.safeParse(values).success).toBe(false);
    }

    expect(organizationStepTwoSchema.safeParse({
      phone: "+543705234524",
      contactEmail: "administracion@taller-personalizado.com.ar",
    }).success).toBe(true);
  });

  it("persiste solamente el Paso 2 para la organización derivada de la sesión", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190006_owner_setup_step_two.sql"), "utf8");
    const action = readFileSync(join(process.cwd(), "src/features/organizations/step-two-actions.ts"), "utf8");
    expect(migration).toContain("public.current_organization_id()");
    expect(migration).toContain("public.current_app_role() <> 'OWNER'");
    expect(migration).toContain("initial_setup_step = greatest(initial_setup_step, 3)");
    expect(migration).toContain("initial_setup_completed = false");
    expect(migration).toContain("initial_setup_step >= 2");
    expect(migration).not.toContain("initial_setup_completed = true");
    expect(action).not.toContain("organization_id: formData");
    expect(action).not.toContain("auth.updateUser");
  });

  it("valida los campos estructurados y admite altura o S/N de forma excluyente", () => {
    const base = {
      countryId: "AR",
      provinceId: "34",
      localityId: "34014020",
      neighborhoodId: "",
      street: "  Av. 25   de Mayo ",
      streetNumber: "1250",
      withoutNumber: false,
      floor: " PB ",
      apartment: "2C",
      postalCode: " p3600abc ",
      reference: " Frente a la plaza ",
    };
    expect(organizationStepThreeSchema.parse(base)).toMatchObject({
      street: "Av. 25 de Mayo",
      streetNumber: 1250,
      floor: "PB",
      postalCode: "P3600ABC",
    });
    expect(organizationStepThreeSchema.parse({ ...base, streetNumber: "", withoutNumber: true }).streetNumber).toBeNull();
    expect(organizationStepThreeSchema.safeParse({ ...base, provinceId: "" }).success).toBe(false);
    expect(organizationStepThreeSchema.safeParse({ ...base, localityId: "" }).success).toBe(false);
    expect(organizationStepThreeSchema.safeParse({ ...base, street: " " }).success).toBe(false);
    expect(organizationStepThreeSchema.safeParse({ ...base, streetNumber: "12A" }).success).toBe(false);
  });

  it("limpia selecciones dependientes incompatibles", () => {
    const selection = { countryId: "AR", provinceId: "34", localityId: "34014020", neighborhoodId: "barrio-1" };
    expect(selectProvince(selection, "06")).toEqual({ countryId: "AR", provinceId: "06", localityId: "", neighborhoodId: "" });
    expect(selectLocality(selection, "otra-localidad")).toEqual({ ...selection, localityId: "otra-localidad", neighborhoodId: "" });
  });

  it("protege jerarquía, evita domicilios duplicados y conserva onboarding pendiente", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190007_owner_setup_step_three.sql"), "utf8");
    const action = readFileSync(join(process.cwd(), "src/features/organizations/step-three-actions.ts"), "utf8");
    expect(migration).toContain("foreign key (province_id, country_id)");
    expect(migration).toContain("foreign key (locality_id, province_id)");
    expect(migration).toContain("foreign key (neighborhood_id, locality_id)");
    expect(migration).toContain("organization_id uuid not null unique");
    expect(migration).toContain("on conflict (organization_id) do update");
    expect(migration).toContain("initial_setup_step = greatest(initial_setup_step, 4)");
    expect(migration).toContain("initial_setup_completed = false");
    expect(migration).not.toContain("initial_setup_completed = true");
    expect(action).not.toContain("organization_id: formData");
    const writeGuard = readFileSync(join(process.cwd(), "supabase/migrations/202608190008_owner_address_write_guard.sql"), "utf8");
    expect(writeGuard).toContain("revoke insert, update, delete on table public.organization_addresses");
  });

  it("formatea una dirección humana sin perder su estructura", () => {
    expect(formatAddress({
      street: "Av. 25 de Mayo",
      street_number: 1250,
      without_number: false,
      floor: "PB",
      apartment: "A",
      postal_code: "P3600ABC",
      reference: "Frente a la plaza",
      neighborhood: null,
      locality: "Formosa",
      province: "Formosa",
      country: "Argentina",
    })).toBe("Av. 25 de Mayo 1250, Piso PB, Depto. A, Formosa, Formosa, P3600ABC, Argentina, Referencia: Frente a la plaza");
  });

  it("finaliza el onboarding de forma atómica, idempotente y sin exigir logo", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190009_finalize_owner_initial_setup.sql"), "utf8");
    expect(migration).toContain("for update");
    expect(migration).toContain("initial_setup_completed = true");
    expect(migration).toContain("initial_setup_step = 4");
    expect(migration).toContain("INITIAL_SETUP_COMPLETED");
    expect(migration).toContain("ALREADY_COMPLETED");
    expect(migration).toContain("SUSPENDED");
    expect(migration).toContain("'ORGANIZATION'::text");
    expect(migration).toContain("'CONTACT'::text");
    expect(migration).toContain("'LOCATION'::text");
    expect(migration).not.toContain("logo_path is null");
    const fix = readFileSync(join(process.cwd(), "supabase/migrations/202608190010_fix_finalize_setup_status_ambiguity.sql"), "utf8");
    expect(fix).toContain("p.status = 'ACTIVE'");
  });

  it("deriva la organización en servidor y el resumen se construye con datos persistidos", () => {
    const action = readFileSync(join(process.cwd(), "src/features/organizations/finalize-setup-action.ts"), "utf8");
    const page = readFileSync(join(process.cwd(), "src/app/(admin)/initial-setup/page.tsx"), "utf8");
    const confirmation = readFileSync(join(process.cwd(), "src/features/organizations/components/OrganizationStepFourConfirmation.tsx"), "utf8");
    expect(action).toContain("finalize_initial_organization_setup");
    expect(action).not.toContain("formData.get");
    expect(action).not.toContain('formData.get("organizationId")');
    expect(page).toContain("buildInitialSetupConfirmationData");
    expect(page).toContain('redirect("/dashboard")');
    expect(confirmation).toContain("onEdit(0)");
    expect(confirmation).toContain("onEdit(1)");
    expect(confirmation).toContain("onEdit(2)");
    expect(confirmation).not.toContain("window.confirm");
  });

  it("utiliza el nombre comercial y conserva la razón social como fallback", () => {
    expect(getOrganizationDisplayName({ name: "R&R Asociados S.R.L.", trade_name: "R&R" })).toBe("R&R");
    expect(getOrganizationDisplayName({ name: "Juan Pérez", trade_name: null })).toBe("Juan Pérez");
  });

  it("normaliza y valida los campos fundamentales", () => {
    const result = organizationSetupSchema.parse({
      name: "  Nodo Service Tech  ",
      tradeName: "Nodo Reparaciones",
      phone: "+54 370 4000000",
      contactEmail: "CONTACTO@NODO.TEST",
      address: "Av. Principal 123",
      locality: "Formosa",
      province: "Formosa",
      description: "Servicio técnico con seguimiento claro.",
    });
    expect(result.name).toBe("Nodo Service Tech");
    expect(result.contactEmail).toBe("contacto@nodo.test");
  });

  it("rechaza datos incompletos o formatos inválidos", () => {
    expect(organizationSetupSchema.safeParse({ name: "N", tradeName: "", phone: "abc", contactEmail: "correo", address: "", locality: "", province: "", description: "corta" }).success).toBe(false);
  });
});

describe("creación de organizaciones por SUPERADMIN", () => {
  it("normaliza el nombre y compara duplicados sin distinguir mayúsculas", () => {
    expect(normalizeOrganizationName("  Nodo   Service  ")).toBe("Nodo Service");
    expect(normalizeOrganizationNameForComparison("Nodo Service")).toBe(
      normalizeOrganizationNameForComparison("  nodo   service "),
    );
  });

  it("acepta los caracteres definidos para nombre e identificador", () => {
    expect(organizationNameSchema.parse("Nodo_Service 2026")).toBe("Nodo_Service 2026");
    expect(organizationSlugSchema.parse("NODO_service-2026")).toBe("nodo_service-2026");
  });

  it("rechaza identificadores cortos, con espacios o símbolos", () => {
    for (const value of ["n", "nodo service", "nodo@service"]) {
      expect(organizationSlugSchema.safeParse(value).success).toBe(false);
    }
  });
});

describe("gestión de usuarios por SUPERADMIN", () => {
  it("pagina listas en grupos de cinco y calcula el rango visible", () => {
    const records = Array.from({ length: 12 }, (_, index) => index + 1);
    expect(paginate(records, 2)).toEqual([6, 7, 8, 9, 10]);
    expect(pageRange(3, records.length)).toEqual({ start: 11, end: 12 });
  });

  it("normaliza nombres e impide roles arbitrarios en invitaciones", () => {
    expect(normalizePersonName("  María   O'Connor ")).toBe("María O'Connor");
    expect(inviteUserSchema.safeParse({ firstName: "María", lastName: "O'Connor", email: "maria@example.test", role: "SUPERADMIN", organizationId: "3bcf5b46-758c-4995-9ade-ba7d963ad43c" }).success).toBe(false);
  });

  it("exige confirmación reforzada únicamente al elevar el rol", () => {
    expect(requiredRoleConfirmation("CUSTOMER", "OWNER")).toBe("ADMINISTRADOR");
    expect(requiredRoleConfirmation("OWNER", "SUPERADMIN")).toBe("SUPERADMIN");
    expect(requiredRoleConfirmation("OWNER", "OWNER")).toBeNull();
    expect(requiredRoleConfirmation("OWNER", "CUSTOMER")).toBeNull();
  });
});

describe("perfil y horario de SUPERADMIN", () => {
  it("calcula el saludo usando America/Argentina/Buenos_Aires", () => {
    expect(argentinaGreeting(new Date("2026-08-19T08:00:00Z"))).toBe("Buenos días");
    expect(argentinaGreeting(new Date("2026-08-19T15:00:00Z"))).toBe("Buenas tardes");
    expect(argentinaGreeting(new Date("2026-08-19T23:00:00Z"))).toBe("Buenas noches");
    expect(argentinaGreeting(new Date("2026-08-19T07:59:00Z"))).toBe("Buenas noches");
    expect(formatArgentinaDateTime("2026-08-19T23:35:00Z")).toContain("20:35");
    expect(formatArgentinaLongDate("2026-08-19T15:00:00Z")).toBe("Miércoles, 19 de agosto de 2026");
  });

  it("separa datos personales de campos administrativos", () => {
    const result = superadminProfileSchema.parse({ firstName: " Lada ", lastName: " Rodriguez ", displayName: "Lada Rodriguez", role: "SUPERADMIN", status: "DISABLED" });
    expect(result).toEqual({ firstName: "Lada", lastName: "Rodriguez", displayName: "Lada Rodriguez" });
    expect("role" in result).toBe(false);
    expect("status" in result).toBe(false);
  });

  it("exige contraseña actual y coincidencia de la nueva contraseña", () => {
    expect(superadminPasswordSchema.safeParse({ currentPassword: "", password: "Clave-Nueva-2026!", confirmPassword: "Clave-Nueva-2026!" }).success).toBe(false);
    expect(superadminPasswordSchema.safeParse({ currentPassword: "Actual-Segura-2025!", password: "Clave-Nueva-2026!", confirmPassword: "otra" }).success).toBe(false);
  });
});

describe("dashboard operativo del OWNER", () => {
  it("traduce eventos propios sin exponer metadata técnica", () => {
    expect(ownerActivityLabel("INITIAL_SETUP_COMPLETED")).toBe("Configuración inicial completada");
    expect(ownerActivityLabel("REPAIR_STATUS_CHANGED")).toBe("Estado de reparación actualizado");
  });

  it("pagina auditoría por organización y mantiene demos fuera de producción", () => {
    const dataSource = readFileSync(join(process.cwd(), "src/features/dashboard/data.ts"), "utf8");
    const demoGuard = readFileSync(join(process.cwd(), "src/lib/demo.ts"), "utf8");
    expect(dataSource).toContain("OWNER_ACTIVITY_PAGE_SIZE = 5");
    expect(dataSource).toContain('.eq("organization_id", organization.id)');
    expect(dataSource).toContain('.order("created_at", { ascending: false })');
    expect(demoGuard).toContain('process.env.NODE_ENV === "development"');
  });

  it("comparte el contexto OWNER y consulta actividad con conteo en una sola operación normal", () => {
    const setup = readFileSync(join(process.cwd(), "src/lib/organizations/setup.ts"), "utf8");
    const dataSource = readFileSync(join(process.cwd(), "src/features/dashboard/data.ts"), "utf8");
    expect(setup).toContain("const readOwnerOrganization = cache(");
    expect(setup).toContain('requireRole(["OWNER"])');
    expect(dataSource).toContain('{ count: "exact" }');
    expect(dataSource).toContain('.eq("organization_id", organization.id)');
    expect(dataSource).not.toContain("searchParams.organization_id");
  });

  it("mantiene una sola CTA principal y usa el empty state como alternativa", () => {
    const dashboard = readFileSync(join(process.cwd(), "src/app/(admin)/dashboard/page.tsx"), "utf8");
    const hero = readFileSync(join(process.cwd(), "src/features/dashboard/components/OwnerDashboardHero.tsx"), "utf8");
    const recent = readFileSync(join(process.cwd(), "src/features/dashboard/components/RecentRepairs.tsx"), "utf8");
    expect(dashboard).toContain("showPrimaryAction={dashboard.repairs.length > 0}");
    expect(hero).toContain("Nueva reparación");
    expect(recent).toContain("Crear primera reparación");
    expect(dashboard).not.toContain("Nueva reparación");
  });

  it("no inventa notificaciones y evita repetir textos de gestión en el header", () => {
    const header = readFileSync(join(process.cwd(), "src/components/layout/AppHeader.tsx"), "utf8");
    expect(header).toContain('aria-label="Notificaciones, sin novedades"');
    expect(header).not.toContain("Panel de gestión");
    expect(header).not.toMatch(/badge[^\n]*[1-9]/i);
  });

  it("mantiene el dashboard oscuro neutral y el azul como acento", () => {
    const styles = readFileSync(join(process.cwd(), "src/app/globals.css"), "utf8");
    expect(styles).toContain('[data-theme="dark"] .owner-shell');
    expect(styles).toContain("--app-page: #0c0f14");
    expect(styles).toContain("--app-card: #171c24");
    expect(styles).toContain("--accent-button: #2563eb");
  });
});

describe("agenda del OWNER", () => {
  it("obtiene la fecha real de Argentina y localiza el mes en español", () => {
    expect(argentinaDateKey(new Date("2026-08-19T15:00:00Z"))).toBe("2026-08-19");
    expect(argentinaDateKey(new Date("2026-08-19T02:30:00Z"))).toBe("2026-08-18");
    expect(formatMonthLabel(2026, 7)).toBe("Agosto de 2026");
    expect(formatCalendarAriaLabel("2026-08-19", 2)).toBe("19 de agosto de 2026, 2 eventos");
  });

  it("construye semanas desde el lunes y navega correctamente entre meses", () => {
    const august = buildCalendarMonth(2026, 7, "2026-08-19");
    expect(august[0]?.dateKey).toBe("2026-07-27");
    expect(august.find((day) => day.dateKey === "2026-08-19")).toMatchObject({ isToday: true, inCurrentMonth: true });
    expect(shiftCalendarMonth(2026, 0, -1)).toEqual({ year: 2025, monthIndex: 11 });
    expect(shiftCalendarMonth(2026, 11, 1)).toEqual({ year: 2027, monthIndex: 0 });
    expect(addCivilDays("2026-08-31", 1)).toBe("2026-09-01");
    expect(agendaWindowRange("2026-08-19")).toEqual({ start: "2026-07-01", end: "2026-09-30" });
  });

  it("ordena los eventos con hora y deja los de día completo al final", () => {
    const base = { organizationId: "org-a", date: "2026-08-19", type: AGENDA_EVENT_TYPES.GENERAL } as const;
    const events: AgendaEvent[] = [
      { ...base, id: "all-day", time: null, title: "Durante el día" },
      { ...base, id: "late", time: "16:30", title: "Tarde" },
      { ...base, id: "early", time: "09:30", title: "Mañana" },
    ];
    expect(groupAgendaEvents(events).get("2026-08-19")?.map((event) => event.id)).toEqual(["early", "late", "all-day"]);
  });

  it("consulta por rango y organización y mantiene eventos ficticios sólo en desarrollo", () => {
    const repository = readFileSync(join(process.cwd(), "src/features/dashboard/agenda/repository.ts"), "utf8");
    const calendar = readFileSync(join(process.cwd(), "src/features/dashboard/agenda/AgendaCalendar.tsx"), "utf8");
    expect(repository).toContain("event.organizationId === organizationId");
    expect(repository).toContain("event.date >= start && event.date <= end");
    expect(repository).toContain("isDemoDataEnabled");
    expect(calendar).toContain('aria-current={day.isToday ? "date" : undefined}');
    expect(calendar).toContain("ArrowLeft");
    expect(calendar).toContain("ArrowDown");
  });
});

describe("clima del OWNER", () => {
  const formosa: WeatherLocation = { countryCode: "AR", countryName: "Argentina", locality: "Formosa", province: "Formosa" };

  it("resuelve Formosa y diferencia localidades usando provincia y país", () => {
    const coordinates = resolveOpenMeteoCoordinates([
      { name: "Formosa", admin1: "Goiás", country_code: "BR", latitude: -15.5, longitude: -47.3 },
      { name: "Formosa", admin1: "Formosa", country_code: "AR", latitude: -26.1849, longitude: -58.1731 },
    ], formosa);
    expect(coordinates).toEqual({ latitude: -26.1849, longitude: -58.1731 });
    expect(resolveOpenMeteoCoordinates([
      { name: "San Rafael", admin1: "Mendoza", country_code: "AR", latitude: -34.6177, longitude: -68.3301 },
    ], { ...formosa, locality: "San Rafael", province: "Mendoza" })).toEqual({ latitude: -34.6177, longitude: -68.3301 });
    expect(resolveOpenMeteoCoordinates([], formosa)).toBeNull();
  });

  it("envía sólo contexto geográfico mínimo y fija unidades argentinas", () => {
    const geocoding = new URL(buildOpenMeteoGeocodingUrl(formosa));
    expect(geocoding.searchParams.get("name")).toBe("Formosa, Formosa");
    expect(geocoding.searchParams.get("countryCode")).toBe("AR");
    expect([...geocoding.searchParams.keys()].sort()).toEqual(["count", "countryCode", "format", "language", "name"].sort());

    const forecast = new URL(buildOpenMeteoForecastUrl(-26.1849, -58.1731));
    expect(forecast.searchParams.get("temperature_unit")).toBe("celsius");
    expect(forecast.searchParams.get("wind_speed_unit")).toBe("kmh");
    expect(forecast.searchParams.get("timezone")).toBe("America/Argentina/Buenos_Aires");
    expect(forecast.searchParams.get("forecast_days")).toBe("1");
  });

  it("normaliza temperatura, humedad, viento, lluvia y mínima/máxima", () => {
    const weather = mapOpenMeteoForecast({
      current: { temperature_2m: 22.4, apparent_temperature: 23.1, relative_humidity_2m: 71, wind_speed_10m: 12.5, weather_code: 2, is_day: 1, time: 1_787_143_200 },
      daily: { temperature_2m_min: [15.2], temperature_2m_max: [27.6], precipitation_probability_max: [35] },
    }, formosa);
    expect(weather).toMatchObject({
      temperature: 22.4,
      apparentTemperature: 23.1,
      humidity: 71,
      windSpeed: 12.5,
      precipitationProbability: 35,
      minTemperature: 15.2,
      maxTemperature: 27.6,
      condition: "Parcialmente nublado",
      location: "Formosa, Formosa",
    });
    expect(mapOpenMeteoForecast({ current: {} }, formosa)).toBeNull();
  });

  it("traduce centralmente los códigos meteorológicos", () => {
    expect(weatherConditionFromCode(0).label).toBe("Despejado");
    expect(weatherConditionFromCode(45).label).toBe("Niebla");
    expect(weatherConditionFromCode(63).label).toBe("Lluvia");
    expect(weatherConditionFromCode(95).label).toBe("Tormenta");
  });

  it("mantiene caché, timeout, errores locales y ubicación derivada del servidor", () => {
    const provider = readFileSync(join(process.cwd(), "src/features/dashboard/weather/open-meteo-provider.ts"), "utf8");
    const dashboardData = readFileSync(join(process.cwd(), "src/features/dashboard/data.ts"), "utf8");
    expect(provider).toContain("WEATHER_REVALIDATE_SECONDS = 1_200");
    expect(provider).toContain("GEOCODING_REVALIDATE_SECONDS = 86_400");
    expect(provider).toContain("AbortSignal.timeout");
    expect(provider).toContain('status: "provider-error"');
    expect(provider).toContain('status: "location-unavailable"');
    expect(dashboardData).toContain("address.country_id");
    expect(dashboardData).not.toContain("searchParams.organization_id");
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
    expect(canAccessSuperadmin("CUSTOMER")).toBe(false);
    expect(canAccessSuperadmin(null)).toBe(false);
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

describe("consolidación de seguridad SUPERADMIN", () => {
  const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190003_superadmin_consolidation.sql"), "utf8");

  it("bloquea acceso operativo de organizaciones suspendidas pero preserva inspección SUPERADMIN", () => {
    expect(organizationAllowsOperationalAccess("OWNER", "SUSPENDED")).toBe(false);
    expect(organizationAllowsOperationalAccess("CUSTOMER", "SUSPENDED")).toBe(false);
    expect(organizationAllowsOperationalAccess("TECHNICIAN", "SUSPENDED")).toBe(false);
    expect(organizationAllowsOperationalAccess("OWNER", "ACTIVE")).toBe(true);
    expect(organizationAllowsOperationalAccess("SUPERADMIN", "SUSPENDED")).toBe(true);
  });

  it("garantiza transaccionalmente que quede un SUPERADMIN activo", () => {
    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toContain("LAST_ACTIVE_SUPERADMIN");
    expect(migration).toContain("role = 'SUPERADMIN' and status = 'ACTIVE'");
  });

  it("registra suspensión y reactivación en la misma función de datos", () => {
    expect(migration).toContain("admin_set_organization_status");
    expect(migration).toContain("ORGANIZATION_SUSPENDED");
    expect(migration).toContain("ORGANIZATION_REACTIVATED");
  });

  it("mantiene auditoría append-only y rechaza metadata sensible", () => {
    const foundation = readFileSync(join(process.cwd(), "supabase/migrations/202608170001_auth_foundation.sql"), "utf8");
    expect(foundation).toContain("revoke insert, update, delete on table public.audit_events");
    expect(migration).toContain("(password|token|secret|cookie|authorization)");
  });

  it("usa el factor TOTP y la verificación oficial de Supabase", () => {
    const mfaComponent = readFileSync(join(process.cwd(), "src/features/superadmin/components/MfaSecurity.tsx"), "utf8");
    const challenge = readFileSync(join(process.cwd(), "src/features/auth/components/MfaChallengeForm.tsx"), "utf8");
    expect(mfaComponent).toContain('factorType: "totp"');
    expect(mfaComponent).toContain("auth.mfa.enroll");
    expect(challenge).toContain("auth.mfa.challengeAndVerify");
    expect(mfaComponent).not.toContain("localStorage");
  });

  it("mantiene paginación de cinco elementos", () => {
    expect(paginate(Array.from({ length: 17 }, (_, index) => index), 3)).toHaveLength(5);
    expect(pageRange(4, 17)).toEqual({ start: 16, end: 17 });
  });
});

describe("accesos rápidos personales del OWNER", () => {
  it("acepta HTTPS únicamente para hosts permitidos y sus subdominios", () => {
    expect(validateQuickLinkUrl("INSTAGRAM", "https://www.instagram.com/nodo")).toBe("https://www.instagram.com/nodo");
    expect(validateQuickLinkUrl("GMAIL", "https://mail.google.com/mail/u/0/")).toBe("https://mail.google.com/mail/u/0/");
    expect(validateQuickLinkUrl("YOUTUBE", "https://youtu.be/demo")).toBe("https://youtu.be/demo");
  });

  it("rechaza protocolos ejecutables o no cifrados", () => {
    for (const url of ["javascript:alert(1)", "data:text/html,test", "file:///tmp/test", "vbscript:msgbox(1)", "http://instagram.com/nodo"]) {
      expect(() => validateQuickLinkUrl("INSTAGRAM", url)).toThrow();
    }
  });

  it("rechaza una URL válida que pertenece a otro servicio", () => {
    expect(() => validateQuickLinkUrl("WHATSAPP", "https://instagram.com/nodo")).toThrow("La URL no corresponde a WhatsApp.");
    expect(() => validateQuickLinkUrl("GOOGLE", "https://google.com.evil.example/")).toThrow();
  });

  it("protege propiedad con RLS y deriva el usuario desde auth.uid", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608190004_owner_quick_links.sql"), "utf8");
    expect(migration).toContain("user_id = auth.uid()");
    expect(migration).toContain("default auth.uid()");
    expect(migration).toContain("unique (user_id, service)");
    expect(migration).toContain("quick_link_url_allowed");
    expect(migration).not.toContain("service_role");
  });
});
