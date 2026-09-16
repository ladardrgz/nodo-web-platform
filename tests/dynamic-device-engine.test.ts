import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  "supabase/migrations/202608310007_catalogo_procesadores_pc.sql",
  "utf8",
);
const receptionData = readFileSync(
  "src/features/repairs/reception/data.ts",
  "utf8",
);
const deviceCatalogHook = readFileSync("src/features/repairs/reception/hooks/useDeviceCatalogs.ts", "utf8");
const receptionActions = readFileSync(
  "src/features/repairs/reception/actions.ts",
  "utf8",
);
const pcMigration = readFileSync(
  "supabase/migrations/202608310008_completar_formulario_pc_y_catalogos.sql",
  "utf8",
);
const stepTwoMigration = readFileSync("supabase/migrations/20260905004955_configure_dynamic_device_step.sql", "utf8");
const sectionRenderer = readFileSync("src/features/repairs/reception/device/DeviceFormSection.tsx", "utf8");
const deviceRenderer = readFileSync("src/features/repairs/reception/device/DeviceDynamicForm.tsx", "utf8");
const repeatables = readFileSync("src/features/repairs/reception/device/RepeatableDeviceFields.tsx", "utf8");
const gpuCleanupMigration = readFileSync("supabase/migrations/20260905013658_remove_legacy_gpu_hardware_catalog.sql", "utf8");
const processorRpcMigration = readFileSync("supabase/migrations/20260905142420_add_compatible_processor_catalog_rpcs.sql", "utf8");
const dynamicFieldRenderer = readFileSync("src/features/repairs/reception/device/DynamicFieldRenderer.tsx", "utf8");
const canonicalPersistenceMigration = readFileSync("supabase/migrations/20260916174500_canonical_device_catalog_persistence.sql", "utf8");
const superadminMigration = readFileSync("supabase/migrations/20260916165243_superadmin_master_catalog_console.sql", "utf8");

describe("catálogo normalizado de procesadores para PC", () => {
  it("separa marca, familia y modelo y conserva una única selección por dispositivo", () => {
    expect(migration).toContain("create table public.marcas_procesador");
    expect(migration).toContain("create table public.familias_procesador");
    expect(migration).toContain("create table public.modelos_procesador");
    expect(migration).toContain("create table public.procesadores_dispositivos");
    expect(migration).toContain(
      "constraint uq_procesadores_dispositivos_dispositivo unique (fk_dispositivo_cliente_id)",
    );
  });

  it("protege duplicados normalizados incluso ante inserciones concurrentes", () => {
    expect(migration).toContain(
      "constraint uq_marcas_procesador_nombre_normalizado unique (nombre_normalizado)",
    );
    expect(migration).toContain(
      "constraint uq_familias_procesador_nombre unique (fk_marca_procesador_id, nombre_normalizado)",
    );
    expect(migration).toContain(
      "unique nulls not distinct (fk_familia_procesador_id, nombre_normalizado, fk_organizacion_id)",
    );
    expect(migration).toContain("public.normalizar_nombre_catalogo(v_nombre)");
  });

  it("valida en servidor la cadena marca-familia-modelo y exige procesador para PC", () => {
    expect(migration).toContain("raise exception 'PROCESSOR_REQUIRED'");
    expect(migration).toContain("raise exception 'INVALID_PROCESSOR_FAMILY'");
    expect(migration).toContain("raise exception 'INVALID_PROCESSOR'");
    expect(migration).toContain(
      "fp.fk_marca_procesador_id=p_marca_procesador_id",
    );
  });

  it("aísla los modelos privados y audita las altas autorizadas", () => {
    expect(migration).toContain(
      "alcance = 'GLOBAL' or fk_organizacion_id = public.current_organization_id()",
    );
    expect(migration).toContain(
      "revoke insert, update, delete on table public.marcas_procesador",
    );
    expect(migration).toContain("v_org uuid:=public.assert_reception_owner()");
    expect(migration).toContain("'MODELO_PROCESADOR_CREADO'");
  });

  it("consulta en servidor sólo los modelos compatibles y encadena marca, familia y modelo", () => {
    expect(receptionActions).toContain('rpc("get_compatible_processor_brands"');
    expect(receptionActions).toContain('rpc("get_compatible_processor_families"');
    expect(receptionActions).toContain('rpc("get_compatible_processor_generations"');
    expect(receptionActions).toContain('rpc("get_compatible_processor_models"');
    expect(deviceCatalogHook).toContain("getCompatibleProcessorFamiliesAction");
    expect(deviceCatalogHook).toContain("getCompatibleProcessorGenerationsAction");
    expect(deviceCatalogHook).toContain("getCompatibleProcessorModelsAction");
    expect(receptionActions).not.toContain("getCompatibleProcessorCatalogAction");
  });

  it("incluye los extremos del catálogo solicitado para AMD e Intel", () => {
    expect(migration).toContain("('AMD','Athlon','200GE')");
    expect(migration).toContain("('AMD','Ryzen 9','9950X')");
    expect(migration).toContain("('Intel','Celeron','G1610')");
    expect(migration).toContain("('Intel','Core Ultra 9','285K')");
  });
});

describe("consola maestra y persistencia canónica", () => {
  it("protege las mutaciones globales dentro de PostgreSQL", () => {
    expect(superadminMigration).toContain("public.assert_superadmin_catalog()");
    expect(superadminMigration).toContain("security definer set search_path=''");
    expect(superadminMigration).toContain("revoke all on function public.superadmin_create_device_brand");
  });

  it("guarda las relaciones canónicas y rechaza jerarquías incompatibles", () => {
    expect(canonicalPersistenceMigration).toContain("fk_variante_modelo_dispositivo_id=v_variant_id");
    expect(canonicalPersistenceMigration).toContain("fk_color_dispositivo_id=v_color_id");
    expect(canonicalPersistenceMigration).toContain("fk_motherboard_model_id=v_motherboard_model_id");
    expect(canonicalPersistenceMigration).toContain("INVALID_PROCESSOR_COMPATIBILITY");
    expect(canonicalPersistenceMigration).toContain("INVALID_GPU_COMPATIBILITY");
  });

  it("consulta variantes y motherboards por sus dependencias", () => {
    expect(receptionData).not.toContain('from("device_model_variants")');
    expect(receptionActions).toContain("getDeviceModelVariantsAction");
    expect(receptionActions).toContain("getMotherboardModelsAction");
    expect(deviceCatalogHook).toContain("chooseModel");
    expect(deviceCatalogHook).toContain("motherboard_brand_id");
  });
});

describe("formulario completo y configurable de PC", () => {
  it("define gabinete primero y conserva el resto de las secciones en PostgreSQL", () => {
    expect(pcMigration).toContain("('gabinete_fuente','Gabinete y fuente'");
    expect(pcMigration).toContain("update public.secciones_formulario_dispositivo set orden=20 where clave='procesador'");
    expect(pcMigration).toContain("('placa_madre','Placa madre'");
    expect(pcMigration).toContain("('graficos','Tarjeta gráfica'");
    expect(pcMigration).toContain("('refrigeracion_procesador','Refrigeración del procesador'");
    expect(pcMigration).toContain("('sistema_operativo','Sistema operativo'");
    expect(pcMigration).toContain("('conectividad_wifi','Conectividad Wi-Fi'");
  });

  it("modela componentes, RAM, almacenamiento y accesorios sin listas frontend", () => {
    expect(pcMigration).toContain("create table public.marcas_componente");
    expect(pcMigration).toContain("create table public.modelos_componente");
    expect(pcMigration).toContain("create table public.memoria_ram_dispositivo");
    expect(pcMigration).toContain("create table public.almacenamientos_dispositivo");
    expect(pcMigration).toContain("create table public.accesorios_dispositivo");
    expect(receptionData).toContain('supabase.from("component_brands")');
    expect(receptionData).toContain('supabase.from("storage_types")');
    expect(receptionData).toContain('supabase.from("device_accessories")');
  });

  it("valida exclusiones condicionales y persiste todo en una RPC transaccional", () => {
    expect(pcMigration).toContain("raise exception 'DUPLICATED_POWER_SUPPLY'");
    expect(pcMigration).toContain("raise exception 'DEDICATED_GPU_REQUIRED'");
    expect(pcMigration).toContain("raise exception 'EXTERNAL_CPU_COOLER_REQUIRED'");
    expect(pcMigration).toContain("raise exception 'OPERATING_SYSTEM_VERSION_REQUIRED'");
    expect(pcMigration).toContain("raise exception 'EXTERNAL_WIFI_REQUIRED'");
    expect(pcMigration).toContain("jsonb_array_elements(p_memorias)");
    expect(pcMigration).toContain("jsonb_array_elements(p_almacenamientos)");
    expect(pcMigration).toContain("jsonb_array_elements(p_accesorios)");
  });

  it("impide escrituras directas y aísla catálogos privados por organización", () => {
    expect(pcMigration).toContain("alter table public.marcas_componente enable row level security");
    expect(pcMigration).toContain("fk_organizacion_id=public.current_organization_id()");
    expect(pcMigration).toContain("revoke insert,update,delete on table public.categorias_componente");
    expect(pcMigration).toContain("v_org uuid:=public.assert_reception_owner()");
  });
});

describe("Paso 2 dinámico de Notebook", () => {
  it("define desde base las once secciones ordenadas y un layout controlado", () => {
    for (const title of ["Identificación", "Procesador", "Memoria RAM", "Gráficos", "Almacenamiento", "Pantalla", "Batería y cargador", "Sistema operativo", "Conectividad", "Puertos", "Accesorios"]) expect(stepTwoMigration).toContain(`'${title}'`);
    expect(sectionRenderer).toContain("containerVariants");
    expect(sectionRenderer).toContain("columnVariants");
    expect(sectionRenderer).not.toContain("section.uiConfig.container}");
  });

  it("usa un registry cerrado para los campos complejos", () => {
    for (const component of ["ram-modules", "storage-drives", "device-ports", "multi-select", "searchable-select"]) expect(stepTwoMigration).toContain(`\"component\":\"${component}\"`);
    expect(deviceRenderer).toContain("RamModulesField");
    expect(deviceRenderer).toContain("StorageDrivesField");
    expect(deviceRenderer).toContain("DevicePortsField");
    expect(deviceRenderer).not.toContain("eval(");
  });

  it("persiste y recupera hardware repetible en tablas canónicas", () => {
    for (const table of ["customer_device_ram_modules", "customer_device_storage_drives", "customer_device_ports", "customer_device_connectivity", "customer_device_hardware_profiles"]) expect(stepTwoMigration).toContain(table);
    expect(receptionActions).toContain("getDeviceStepTwoAction");
    expect(receptionActions).toContain('from("customer_device_ram_modules")');
    expect(repeatables).toContain("Capacidad (GB)");
    expect(repeatables).toContain("Estado");
  });

  it("incluye las cascadas de prueba GFAST, CPU y GPU sin arrays React", () => {
    expect(stepTwoMigration).toContain("'GFAST'");
    expect(stepTwoMigration).toContain("'N-750'");
    for (const value of ["'AMD'", "'Ryzen 5'", "'5000'", "'Ryzen 5 5500U'", "'Iris Xe Graphics'", "'Vega 8'", "'RTX 3050'"]) expect(stepTwoMigration).toContain(value);
    expect(deviceRenderer).not.toMatch(/\[\s*["']Intel["']\s*,\s*["']AMD/);
  });

  it("elimina las tres FK GPU legacy sólo después de validar el mapeo canónico", () => {
    expect(gpuCleanupMigration).toContain("UNRESOLVED_OR_AMBIGUOUS_LEGACY_GPU_BRANDS");
    expect(gpuCleanupMigration).toContain("UNRESOLVED_OR_AMBIGUOUS_LEGACY_GPU_FAMILIES");
    expect(gpuCleanupMigration).toContain("UNRESOLVED_OR_AMBIGUOUS_LEGACY_GPU_MODELS");
    for (const column of ["fk_gpu_chip_brand_id", "fk_gpu_family_id", "fk_gpu_model_id", "fk_gpu_board_brand_id"]) expect(gpuCleanupMigration).toContain(`drop column ${column}`);
    expect(gpuCleanupMigration).toContain("delete from public.hardware_catalog_items where category='GPU_CHIP_BRAND'");
  });
});

describe("cascada CPU compatible por plataforma", () => {
  it("filtra cada nivel en PostgreSQL mediante EXISTS y compatibilidad de especificaciones", () => {
    for (const rpc of ["brands", "families", "generations", "models"]) expect(processorRpcMigration).toContain(`get_compatible_processor_${rpc}`);
    expect(processorRpcMigration).toContain("exists (");
    expect(processorRpcMigration).toContain("s.desktop_supported");
    expect(processorRpcMigration).toContain("s.notebook_supported");
    expect(processorRpcMigration).toContain("m.alcance='GLOBAL' or m.fk_organizacion_id=public.current_organization_id()");
  });

  it("resetea descendientes, separa estados y descarta respuestas obsoletas", () => {
    expect(deviceCatalogHook).toContain('processor_brand_id: ["processor_family_id", "processor_generation_id", "processor_model_id"]');
    expect(deviceCatalogHook).toContain('processor_family_id: ["processor_generation_id", "processor_model_id"]');
    expect(deviceCatalogHook).toContain('processor_generation_id: ["processor_model_id"]');
    expect(deviceCatalogHook).toContain("ProcessorCatalogStates");
    expect(deviceCatalogHook).toContain("request !== processorCatalogRequest.current");
  });

  it("expone loading, error y vacío contextual sin conservar opciones anteriores", () => {
    expect(dynamicFieldRenderer).toContain("Cargando opciones…");
    expect(dynamicFieldRenderer).toContain('role="alert"');
    expect(deviceRenderer).toContain("No hay procesadores compatibles con");
    expect(deviceCatalogHook).toContain("hardware_processor_model\"] = []");
  });
});
