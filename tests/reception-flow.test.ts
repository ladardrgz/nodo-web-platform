import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { DEVICE_TYPE_SEEDS } from "../src/features/repairs/reception/catalogs";
import { calculateCondition, createInspection, serializeInspection } from "../src/features/repairs/reception/inspection";
import { deviceSchema, newCustomerSchema, receptionSchema } from "../src/features/repairs/reception/schemas";

describe("recepción de equipos", () => {
  it("normaliza clientes y valida teléfono argentino y correo opcional", () => {
    expect(newCustomerSchema.parse({ firstName: "  María   José ", lastName: "O'Connor", phone: "3705123456", email: " CLIENTE@EMPRESA.COM.AR " })).toEqual({ firstName: "María José", lastName: "O'Connor", phone: "3705123456", email: "cliente@empresa.com.ar" });
    for (const phone of ["", "3705", "3705 123456", "+543705123456", "3705ABC456", "37051234567"]) expect(newCustomerSchema.safeParse({ firstName: "Ana", lastName: "Paz", phone, email: "" }).success).toBe(false);
    expect(newCustomerSchema.safeParse({ firstName: "Ana2", lastName: "Paz", phone: "3705123456", email: "" }).success).toBe(false);
    expect(newCustomerSchema.safeParse({ firstName: "Ana", lastName: "Paz", phone: "3705123456", email: "usuario@gmailcito" }).success).toBe(false);
  });

  it("precarga más de cincuenta tipos y mantiene la configuración fuera del componente", () => {
    expect(DEVICE_TYPE_SEEDS.length).toBeGreaterThan(50);
    expect(new Set(DEVICE_TYPE_SEEDS.map((item) => item[1])).size).toBe(DEVICE_TYPE_SEEDS.length);
  });

  it("calcula severidad y destaca daños críticos desde reglas centrales", () => {
    const items = createInspection("COMPUTER");
    const updated = items.map((item) => ({ ...item, status: item.key === "hinges" ? "BROKEN" as const : "NO_DAMAGE" as const }));
    expect(calculateCondition(updated)).toMatchObject({ score: 3, label: "Desgaste normal" });
    expect(calculateCondition(updated).critical.map((item) => item.key)).toContain("hinges");
  });

  it("serializa el estado con el contrato esperado por PostgreSQL", () => {
    expect(serializeInspection([{ key: "screen", label: "Pantalla", status: "BROKEN", observation: "Quebrada" }])).toEqual([
      { key: "screen", label: "Pantalla", condition: "BROKEN", observation: "Quebrada" },
    ]);
  });

  it("vuelve a validar dispositivo e inspección en servidor", () => {
    const device = { customerId: crypto.randomUUID(), typeId: crypto.randomUUID(), brandId: crypto.randomUUID(), model: "Galaxy A14", year: "2024", color: "Negro", serialNumber: "ABC", imei1: "123456789012345", imei2: "", attributes: {}, memories: [], storageUnits: [], accessories: ["Cargador"] };
    expect(deviceSchema.safeParse(device).success).toBe(true);
    expect(deviceSchema.safeParse({ ...device, model: " " }).success).toBe(false);
    expect(receptionSchema.safeParse({ customerId: device.customerId, deviceId: crypto.randomUUID(), reportedProblem: "Se apaga durante la carga", observations: "", inspection: [{ key: "screen", label: "Pantalla", status: "BROKEN", observation: "Quebrada" }] }).success).toBe(true);
  });

  it("protege multi-tenant, unicidad, storage y snapshot inmutable en base", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608240001_reception_foundation.sql"), "utf8");
    expect(migration).toContain("customers_organization_phone_unique");
    expect(migration).toContain("customers_organization_email_unique");
    expect(migration).toContain("public.assert_reception_owner()");
    expect(migration).toContain("organization_id=public.current_organization_id()");
    expect(migration).toContain("CONFIRMED_RECEPTION_IMMUTABLE");
    expect(migration).toContain("reception-photos");
    expect(migration).toContain("file_size_limit");
  });

  it("elimina el resumen lateral y aprovecha el ancho principal", () => {
    const wizard = readFileSync(join(process.cwd(), "src/features/repairs/components/NewRepairForm.tsx"), "utf8");
    expect(wizard).not.toContain("Resumen de recepción");
    expect(wizard).not.toContain("<aside");
    expect(wizard).toContain("max-w-6xl");
  });

  it("lista recepciones y clientes reales sin recurrir a mocks operativos", () => {
    const repairsPage = readFileSync(join(process.cwd(), "src/app/(admin)/repairs/page.tsx"), "utf8");
    const repairDetail = readFileSync(join(process.cwd(), "src/app/(admin)/repairs/[id]/page.tsx"), "utf8");
    const customersPage = readFileSync(join(process.cwd(), "src/app/(admin)/customers/page.tsx"), "utf8");
    const repository = readFileSync(join(process.cwd(), "src/features/repairs/repository.ts"), "utf8");
    expect(repairsPage).toContain("listOrganizationRepairs(organization.id)");
    expect(repairDetail).toContain("getOrganizationRepair(organization.id, id)");
    expect(customersPage).toContain("listOrganizationCustomers(organization.id)");
    expect(repairsPage).not.toContain("mockRepairs");
    expect(repairDetail).not.toContain("mockRepairs");
    expect(customersPage).not.toContain("mockCustomers");
    expect(repository).toContain('.eq("organization_id", organizationId)');
    expect(repository).toContain('.eq("id", receptionId)');
    expect(repository).toContain('import "server-only"');
  });
});
