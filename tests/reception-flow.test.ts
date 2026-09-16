import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { calculateCondition, serializeInspection } from "../src/features/repairs/reception/inspection";
import { deviceSchema, newCustomerSchema, receptionSchema } from "../src/features/repairs/reception/schemas";

describe("recepción de equipos", () => {
  it("normaliza clientes y valida teléfono argentino y correo opcional", () => {
    expect(newCustomerSchema.parse({ firstName: "  María   José ", lastName: "O'Connor", phone: "3705123456", email: " CLIENTE@EMPRESA.COM.AR " })).toEqual({ firstName: "María José", lastName: "O'Connor", phone: "3705123456", email: "cliente@empresa.com.ar" });
    for (const phone of ["", "3705", "3705 123456", "+543705123456", "3705ABC456", "37051234567"]) expect(newCustomerSchema.safeParse({ firstName: "Ana", lastName: "Paz", phone, email: "" }).success).toBe(false);
    expect(newCustomerSchema.safeParse({ firstName: "Ana2", lastName: "Paz", phone: "3705123456", email: "" }).success).toBe(false);
    expect(newCustomerSchema.safeParse({ firstName: "Ana", lastName: "Paz", phone: "3705123456", email: "usuario@gmailcito" }).success).toBe(false);
  });

  it("mantiene categorías de equipos sin convertir modelos en tipos", () => {
    const catalogMigration = readFileSync("supabase/migrations/202608240001_reception_foundation.sql", "utf8");
    const cleanupMigration = readFileSync("supabase/migrations/202608290003_cleanup_device_type_catalog.sql", "utf8");
    expect(catalogMigration).toContain("public.device_types");
    expect(cleanupMigration).toContain("Consola de videojuegos");
    expect(cleanupMigration).toContain("Teléfono / Celular");
    expect(cleanupMigration).toContain("PlayStation 5");
  });

  it("obtiene los tipos y campos exclusivamente desde el catálogo normalizado", () => {
    const dataSource = readFileSync(join(process.cwd(), "src/features/repairs/reception/data.ts"), "utf8");
    const form = readFileSync(join(process.cwd(), "src/features/repairs/components/NewRepairForm.tsx"), "utf8");
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202609010001_restore_english_device_domain.sql"), "utf8");
    expect(dataSource).toContain('from("device_types")');
    expect(dataSource).toContain('from("device_type_fields")');
    expect(dataSource).not.toContain("latestTypeUse");
    expect(form).not.toContain("starterTypes");
    expect(migration).toContain("rename to device_types");
    expect(migration).toContain("Desktop PC");
  });

  it("usa el nombre canónico Desktop PC y los retornos actuales de las RPC", () => {
    const actions = readFileSync(join(process.cwd(), "src/features/repairs/reception/actions.ts"), "utf8");
    const catalogsHook = readFileSync(join(process.cwd(), "src/features/repairs/reception/hooks/useDeviceCatalogs.ts"), "utf8");
    expect(catalogsHook).toContain('type?.code !== "desktop_pc"');
    expect(actions).toMatch(/const row = data as \{\s*id: string;\s*name: string;\s*fk_organizacion_id: string \| null;/);
    expect(actions).not.toContain('const row = data as { id: string; nombre: string; fk_organizacion_id: string | null };\n  return { ok: true, message: "Marca registrada correctamente."');
  });

  it("calcula severidad y destaca daños críticos desde reglas centrales", () => {
    const updated = [{ key: "pantalla", label: "Pantalla", critical: true, status: "BROKEN" as const, observation: "" }];
    expect(calculateCondition(updated)).toMatchObject({ score: 3, label: "Desgaste normal" });
    expect(calculateCondition(updated).critical.map((item) => item.key)).toContain("pantalla");
  });

  it("serializa el estado con el contrato esperado por PostgreSQL", () => {
    expect(serializeInspection([{ key: "screen", label: "Pantalla", status: "BROKEN", observation: "Quebrada" }])).toEqual([
      { key: "screen", label: "Pantalla", condition: "BROKEN", observation: "Quebrada" },
    ]);
  });

  it("vuelve a validar dispositivo e inspección en servidor", () => {
    const device = { customerId: crypto.randomUUID(), typeId: crypto.randomUUID(), brandId: crypto.randomUUID(), modelId: crypto.randomUUID(), model: "Galaxy A14", year: "2024", color: crypto.randomUUID(), serialNumber: "ABC", imei1: "", imei2: "", imeis: ["490154203237518"], attributes: {}, memories: [], storageUnits: [], ports: [], accessories: [crypto.randomUUID()] };
    expect(deviceSchema.safeParse(device).success).toBe(true);
    expect(deviceSchema.safeParse({ ...device, model: "x".repeat(121) }).success).toBe(false);
    expect(deviceSchema.safeParse({ ...device, imeis: ["490154203237519"] }).success).toBe(false);
    expect(deviceSchema.safeParse({ ...device, imeis: ["490154203237518", "490154203237518"] }).success).toBe(false);
    expect(receptionSchema.safeParse({ customerId: device.customerId, deviceId: crypto.randomUUID(), reportedProblem: "Se apaga durante la carga", observations: "", inspection: [{ key: "screen", label: "Pantalla", status: "BROKEN", observation: "Quebrada" }], intakeMetadata: { powerState: "NOT_TESTED", imageState: "NOT_TESTED", chargeState: "NOT_TESTED", accessAvailable: "false", accessMethod: "", credentialProvided: false, postState: "", osBootState: "", inventoryStatus: "", powerTestReason: "", receptionItems: [] } }).success).toBe(true);
  });

  it("consulta marca y modelo por dependencia y guarda la identificación con aislamiento tenant", () => {
    const actions = readFileSync(join(process.cwd(), "src/features/repairs/reception/actions.ts"), "utf8");
    const dataSource = readFileSync(join(process.cwd(), "src/features/repairs/reception/data.ts"), "utf8");
    const identification = readFileSync(join(process.cwd(), "src/features/repairs/reception/device/DeviceIdentificationSection.tsx"), "utf8");
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/20260904045822_rebuild_device_identification_domain.sql"), "utf8");
    expect(actions).toContain("getDeviceBrandsAction");
    expect(actions).toContain("getDeviceModelsAction");
    expect(actions).toMatch(/rpc\(\s*"save_customer_device_step_two"/);
    expect(dataSource).not.toContain('from("device_brands")');
    expect(dataSource).not.toContain('from("device_models")');
    expect(identification).toContain("Cargando marcas…");
    expect(identification).toContain("No hay modelos para esta selección");
    expect(migration).toContain("public.assert_reception_owner()");
    expect(migration).toContain("INVALID_DEVICE_MODEL");
    expect(migration).toContain("CUSTOMER_DEVICE_UPDATED");
    expect(migration).toContain("customer_device_operating_systems");
  });

  it("define el hardware de PC de escritorio en catálogos aislados y normalizados", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608300002_desktop_pc_hardware_catalog.sql"), "utf8");
    expect(migration).toContain("hardware_catalog_models_org_unique");
    expect(migration).toContain("public.normalize_catalog_name(name)");
    expect(migration).toContain("validate_desktop_hardware_values");
    expect(migration).toContain("create_hardware_catalog_model");
    expect(migration).toContain("PC de escritorio");
    expect(migration).toContain("Mini PC");
    expect(migration).not.toContain("SSD NVMe");
  });

  it("consolida los seis tipos de computación de escritorio sin borrar historial", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608300003_desktop_computing_catalog_consolidation.sql"), "utf8");
    for (const name of ["PC", "All-In-One - Todo en uno", "Mini-PC", "Estación de trabajo - Workstation", "HPC", "Embebidos - Embedded"]) expect(migration).toContain(name);
    expect(migration).toContain("set is_active = false");
    expect(migration).toContain("PC gamer");
    expect(migration).toContain("Servidor");
  });

  it("mantiene PC y Notebook como los únicos tipos canónicos de sus variantes", () => {
    const migration = readFileSync(join(process.cwd(), "supabase/migrations/202608310006_renombrar_tipo_pc.sql"), "utf8");
    expect(migration).toContain("set nombre = 'PC'");
    expect(migration).toContain("public.tipos_dispositivo");
    expect(migration).toContain("nombre = 'Notebook'");
    expect(migration).toContain("INVALID_CANONICAL_DEVICE_TYPES");
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

  it("lista órdenes de servicio y clientes reales sin recurrir a mocks operativos", () => {
    const repairsPage = readFileSync(join(process.cwd(), "src/app/(admin)/repairs/page.tsx"), "utf8");
    const repairDetail = readFileSync(join(process.cwd(), "src/app/(admin)/repairs/[id]/page.tsx"), "utf8");
    const customersPage = readFileSync(join(process.cwd(), "src/app/(admin)/customers/page.tsx"), "utf8");
    const repository = readFileSync(join(process.cwd(), "src/features/repairs/repository.ts"), "utf8");
    expect(repairsPage).toContain("SupabaseServiceOrderRepository");
    expect(repairDetail).toContain("getOrganizationRepair(organization.id, id)");
    expect(customersPage).toContain("listOrganizationCustomers(organization.id)");
    expect(repairsPage).not.toContain("mockRepairs");
    expect(repairDetail).not.toContain("mockRepairs");
    expect(customersPage).not.toContain("mockCustomers");
    expect(repository).toContain("SupabaseServiceOrderRepository");
    expect(repository).toContain('import "server-only"');
  });

  it("mantiene visible el acceso a una nueva reparación", () => {
    const repairsPage = readFileSync(join(process.cwd(), "src/app/(admin)/repairs/page.tsx"), "utf8");
    const dashboardPage = readFileSync(join(process.cwd(), "src/app/(admin)/dashboard/page.tsx"), "utf8");
    expect(repairsPage).toContain('href="/repairs/new"');
    expect(repairsPage).toContain("Nueva reparación");
    expect(repairsPage).toContain("actions={<ButtonLink");
    expect(dashboardPage).toContain("showPrimaryAction");
    expect(dashboardPage).not.toContain("showPrimaryAction={dashboard.repairs.length > 0}");
  });
});
