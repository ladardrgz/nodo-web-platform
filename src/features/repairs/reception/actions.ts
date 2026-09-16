"use server";

import { revalidatePath } from "next/cache";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  customBrandSchema,
  customColorSchema,
  customModelSchema,
  customerFieldErrors,
  deviceModelFilterSchema,
  deviceSchema,
  deviceTypeFilterSchema,
  dynamicCatalogSchema,
  gpuCatalogFilterSchema,
  newCustomerSchema,
  photoMetadataSchema,
  receptionSchema,
} from "./schemas";
import { serializeInspection } from "./inspection";
import type {
  CatalogOption,
  DeviceStepTwoSnapshot,
  MutationResult,
  ReceptionCustomer,
} from "./types";

type SupportedProcessorDeviceCode = "desktop_pc" | "notebook";

type ProcessorCatalogResult =
  | { ok: true; data: CatalogOption[] }
  | { ok: false; message: string };

type ProcessorCatalogRow = {
  id: string;
  name: string;
  parent_id: string | null;
  secondary_parent_id: string | null;
  organization_id: string | null;
};

function isSupportedProcessorDeviceCode(
  value: string,
): value is SupportedProcessorDeviceCode {
  return value === "desktop_pc" || value === "notebook";
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

/**
 * PASO 2 · DISPOSITIVO — CPU
 * Devuelve únicamente fabricantes que poseen al menos un modelo compatible
 * con Desktop PC o Notebook.
 *
 * Este endpoint es el primer nivel del selector dependiente:
 * Tipo de dispositivo → Fabricante CPU.
 */
export async function getCompatibleProcessorBrandsAction(
  deviceTypeCode: string,
): Promise<ProcessorCatalogResult> {
  if (!isSupportedProcessorDeviceCode(deviceTypeCode)) {
    return { ok: true, data: [] };
  }

  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(
    "get_compatible_processor_brands",
    { p_device_type_code: deviceTypeCode },
  );
  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar los fabricantes de procesadores.",
    };
  }

  return {
    ok: true,
    data: (data ?? []).map((row: ProcessorCatalogRow) => ({
      id: row.id,
      name: row.name,
      parentId: row.parent_id ?? undefined,
      secondaryParentId: row.secondary_parent_id ?? undefined,
      organizationId: row.organization_id,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — CPU
 * Segundo nivel:
 * Fabricante CPU → Familias CPU compatibles con el tipo de dispositivo.
 */
export async function getCompatibleProcessorFamiliesAction(input: {
  deviceTypeCode: string;
  brandId: string;
}): Promise<ProcessorCatalogResult> {
  if (
    !isSupportedProcessorDeviceCode(input.deviceTypeCode) ||
    !isUuid(input.brandId)
  ) {
    return { ok: true, data: [] };
  }

  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(
    "get_compatible_processor_families",
    { p_device_type_code: input.deviceTypeCode, p_brand_id: input.brandId },
  );
  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar las familias de procesadores.",
    };
  }

  return {
    ok: true,
    data: (data ?? []).map((row: ProcessorCatalogRow) => ({
      id: row.id,
      name: row.name,
      parentId: row.parent_id ?? undefined,
      secondaryParentId: row.secondary_parent_id ?? undefined,
      organizationId: row.organization_id,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — CPU
 * Tercer nivel:
 * Familia CPU → Generaciones/series que realmente poseen modelos compatibles.
 */
export async function getCompatibleProcessorGenerationsAction(input: {
  deviceTypeCode: string;
  brandId: string;
  familyId: string;
}): Promise<ProcessorCatalogResult> {
  if (
    !isSupportedProcessorDeviceCode(input.deviceTypeCode) ||
    !isUuid(input.brandId) ||
    !isUuid(input.familyId)
  ) {
    return { ok: true, data: [] };
  }

  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(
    "get_compatible_processor_generations",
    {
      p_device_type_code: input.deviceTypeCode,
      p_brand_id: input.brandId,
      p_family_id: input.familyId,
    },
  );
  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar las generaciones de procesadores.",
    };
  }

  return {
    ok: true,
    data: (data ?? []).map((row: ProcessorCatalogRow) => ({
      id: row.id,
      name: row.name,
      parentId: row.parent_id ?? undefined,
      secondaryParentId: row.secondary_parent_id ?? undefined,
      organizationId: row.organization_id,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — CPU
 * Último nivel:
 * Familia + generación/serie → modelos reales compatibles.
 *
 * La generación es obligatoria: incluso las familias históricas poseen una
 * serie canónica en `processor_generations`.
 */
export async function getCompatibleProcessorModelsAction(input: {
  deviceTypeCode: string;
  familyId: string;
  generationId: string;
}): Promise<ProcessorCatalogResult> {
  if (
    !isSupportedProcessorDeviceCode(input.deviceTypeCode) ||
    !isUuid(input.familyId) ||
    !isUuid(input.generationId)
  ) {
    return { ok: true, data: [] };
  }

  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc(
    "get_compatible_processor_models",
    {
      p_device_type_code: input.deviceTypeCode,
      p_family_id: input.familyId,
      p_generation_id: input.generationId,
    },
  );
  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar los modelos de procesadores.",
    };
  }

  return {
    ok: true,
    data: (data ?? []).map((row: ProcessorCatalogRow) => ({
      id: row.id,
      name: row.name,
      parentId: row.parent_id ?? undefined,
      secondaryParentId: row.secondary_parent_id ?? undefined,
      organizationId: row.organization_id,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — RAM
 * Primer nivel del selector RAM.
 */
export async function getRamTypesAction(): Promise<
  MutationResult<CatalogOption[]>
> {
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("ram_types")
    .select("id,name")
    .eq("is_active", true)
    .order("name");

  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar los tipos de memoria RAM.",
    };
  }

  return {
    ok: true,
    message: "Tipos de RAM cargados.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      organizationId: null,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — RAM
 * Segundo nivel:
 * Tipo RAM → frecuencias disponibles para ese tipo.
 */
export async function getRamSpeedsAction(
  ramTypeId: string,
): Promise<MutationResult<CatalogOption[]>> {
  if (!isUuid(ramTypeId)) {
    return {
      ok: false,
      message: "El tipo de memoria RAM seleccionado no es válido.",
    };
  }

  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("ram_speeds")
    .select("id,fk_ram_type_id,mhz")
    .eq("fk_ram_type_id", ramTypeId)
    .eq("is_active", true)
    .order("mhz");

  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar las frecuencias de memoria RAM.",
    };
  }

  return {
    ok: true,
    message: "Frecuencias de RAM cargadas.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: `${row.mhz} MHz`,
      parentId: row.fk_ram_type_id,
      organizationId: null,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — ALMACENAMIENTO
 * Tipos de unidad configurados para la organización o globales.
 */
export async function getStorageTypesAction(): Promise<
  MutationResult<CatalogOption[]>
> {
  const { organization } = await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("storage_types")
    .select("id,nombre,fk_organizacion_id")
    .eq("activo", true)
    .or(`alcance.eq.GLOBAL,fk_organizacion_id.eq.${organization.id}`)
    .order("nombre");

  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar los tipos de almacenamiento.",
    };
  }

  return {
    ok: true,
    message: "Tipos de almacenamiento cargados.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.nombre,
      organizationId: row.fk_organizacion_id,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — ALMACENAMIENTO
 * Interfaces globales: SATA, M.2, NVMe/PCIe, IDE/PATA, etc.
 */
export async function getStorageInterfacesAction(): Promise<
  MutationResult<CatalogOption[]>
> {
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("storage_interfaces")
    .select("id,name")
    .eq("is_active", true)
    .order("name");

  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar las interfaces de almacenamiento.",
    };
  }

  return {
    ok: true,
    message: "Interfaces de almacenamiento cargadas.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      organizationId: null,
    })),
  };
}

/**
 * PASO 2 · DISPOSITIVO — ALMACENAMIENTO
 * Factores de forma globales: 2.5, 3.5, M.2 2280, etc.
 */
export async function getStorageFormFactorsAction(): Promise<
  MutationResult<CatalogOption[]>
> {
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from("storage_form_factors")
    .select("id,name")
    .eq("is_active", true)
    .order("name");

  if (error) {
    return {
      ok: false,
      message: "No se pudieron cargar los factores de forma.",
    };
  }

  return {
    ok: true,
    message: "Factores de forma cargados.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      organizationId: null,
    })),
  };
}

function controlledError(error: unknown, fallback: string): string {
  const message =
    error && typeof error === "object" && "message" in error
      ? String(error.message)
      : "";
  const code =
    error && typeof error === "object" && "code" in error
      ? String(error.code)
      : "";
  if (code === "PGRST202")
    return "La operación solicitada no está disponible en el esquema actual.";
  if (message.includes("CUSTOMER_PHONE_EXISTS"))
    return "Este teléfono ya pertenece a un cliente registrado.";
  if (message.includes("CUSTOMER_EMAIL_EXISTS"))
    return "Este correo electrónico ya pertenece a un cliente registrado.";
  if (message.includes("DEVICE_TYPE_EXISTS"))
    return "Este tipo de dispositivo ya existe.";
  if (message.includes("DEVICE_BRAND_EXISTS"))
    return "Esta marca ya está registrada.";
  if (message.includes("DEVICE_MODEL_EXISTS"))
    return "Este modelo ya está registrado para el tipo y la marca seleccionados.";
  if (message.includes("INVALID_DEVICE_MODEL"))
    return "El modelo seleccionado no corresponde al tipo y marca actuales.";
  if (message.includes("PROCESSOR_REQUIRED"))
    return "Seleccioná la marca, familia y modelo del procesador.";
  if (message.includes("INVALID_PROCESSOR"))
    return "El procesador seleccionado no corresponde a la marca y familia actuales.";
  if (message.includes("DEVICE_COLOR_REQUIRED"))
    return "Seleccioná el color del dispositivo.";
  if (message.includes("INVALID_DEVICE_COLOR"))
    return "El color seleccionado no está disponible para tu organización.";
  if (message.includes("INVALID_CASE_FAN_COUNT"))
    return "Ingresá una cantidad válida de ventiladores del gabinete.";
  if (message.includes("INCLUDED_POWER_SUPPLY_REQUIRED"))
    return "Ingresá el nombre o modelo de la fuente incluida.";
  if (message.includes("DEDICATED_GPU_REQUIRED"))
    return "Seleccioná la marca y el modelo de la tarjeta gráfica dedicada.";
  if (message.includes("EXTERNAL_CPU_COOLER_REQUIRED"))
    return "Seleccioná la marca y el modelo del cooler independiente.";
  if (message.includes("OPERATING_SYSTEM_VERSION_REQUIRED"))
    return "Ingresá la versión o distribución del sistema operativo.";
  if (message.includes("EXTERNAL_WIFI_REQUIRED"))
    return "Seleccioná la marca y el modelo del adaptador Wi-Fi.";
  if (message.includes("INVALID_STORAGE"))
    return "Revisá tipo, capacidad y cantidad de las unidades de almacenamiento.";
  if (message.includes("INVALID_MEMORY"))
    return "Revisá capacidad y cantidad de los módulos de RAM.";
  if (message.includes("INVALID_COMPONENT"))
    return "La marca o el modelo del componente no corresponde al catálogo seleccionado.";
  if (message.includes("DUPLICATED_"))
    return "Hay datos incompatibles cargados en campos condicionales. Revisá la configuración del equipo.";
  if (message.includes("INVALID_INSPECTION"))
    return "La inspección contiene un estado no válido. Revisá el checklist e intentá nuevamente.";
  if (message.includes("INVALID_RECEPTION"))
    return "La recepción está incompleta. Revisá el problema informado y la inspección física.";
  if (message.includes("INVALID_DEVICE"))
    return "El dispositivo seleccionado no pertenece al cliente actual.";
  return fallback;
}

export async function createCustomerAction(
  input: unknown,
): Promise<MutationResult<ReceptionCustomer>> {
  const parsed = newCustomerSchema.safeParse(input);
  if (!parsed.success)
    return {
      ok: false,
      message: "Revisá los datos del cliente.",
      fieldErrors: customerFieldErrors(parsed.error),
    };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .rpc("create_reception_customer", {
      p_first_name: parsed.data.firstName,
      p_last_name: parsed.data.lastName,
      p_phone: parsed.data.phone,
      p_contact_email: parsed.data.email || null,
    })
    .single();
  if (error || !data) {
    const message = controlledError(error, "No se pudo registrar el cliente.");
    return {
      ok: false,
      message,
      fieldErrors: message.includes("teléfono")
        ? { phone: message }
        : message.includes("correo")
          ? { email: message }
          : undefined,
    };
  }
  const row = data as {
    id: string;
    first_name: string;
    last_name: string;
    phone: string;
    contact_email: string | null;
  };
  revalidatePath("/repairs/new");
  return {
    ok: true,
    message: "Cliente registrado correctamente.",
    data: {
      id: row.id,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      email: row.contact_email ?? "",
    },
  };
}

export async function createCustomDeviceTypeAction(
  input: unknown,
): Promise<MutationResult<CatalogOption>> {
  void input;
  return {
    ok: false,
    message:
      "Los tipos de dispositivo son administrados por el catálogo central.",
  };
}

export async function getDeviceBrandsAction(
  input: unknown,
): Promise<MutationResult<CatalogOption[]>> {
  const parsed = deviceTypeFilterSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "El tipo de dispositivo no es válido." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("device_type_brands")
    .select("device_brands!inner(id,name,fk_organizacion_id,is_active)")
    .eq("fk_tipo_dispositivo_id", parsed.data)
    .eq("device_brands.is_active", true);
  if (error)
    return {
      ok: false,
      message: "No se pudieron cargar las marcas para este tipo.",
    };
  const rows = (data ?? [])
    .flatMap((row) => {
      const brand = row.device_brands as unknown as {
        id: string;
        name: string;
        fk_organizacion_id: string | null;
      } | null;
      return brand
        ? [
            {
              id: brand.id,
              name: brand.name,
              organizationId: brand.fk_organizacion_id,
            },
          ]
        : [];
    })
    .sort((left, right) => left.name.localeCompare(right.name, "es"));
  return { ok: true, message: "Marcas cargadas.", data: rows };
}

export async function getDeviceModelsAction(
  input: unknown,
): Promise<MutationResult<import("./types").DeviceModelOption[]>> {
  const parsed = deviceModelFilterSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "La selección de tipo y marca no es válida." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("device_models")
    .select(
      "id,name,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_organizacion_id",
    )
    .eq("fk_tipo_dispositivo_id", parsed.data.typeId)
    .eq("fk_marca_dispositivo_id", parsed.data.brandId)
    .eq("is_active", true)
    .order("name");
  if (error)
    return {
      ok: false,
      message: "No se pudieron cargar los modelos para esta marca.",
    };
  return {
    ok: true,
    message: "Modelos cargados.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      deviceTypeId: row.fk_tipo_dispositivo_id,
      brandId: row.fk_marca_dispositivo_id,
      organizationId: row.fk_organizacion_id,
    })),
  };
}

export async function getDeviceModelVariantsAction(
  modelId: string,
): Promise<MutationResult<import("./types").DeviceVariantOption[]>> {
  if (!isUuid(modelId))
    return { ok: false, message: "El modelo seleccionado no es válido." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("device_model_variants")
    .select("id,name,fk_modelo_dispositivo_id")
    .eq("fk_modelo_dispositivo_id", modelId)
    .eq("is_active", true)
    .order("name");
  if (error)
    return {
      ok: false,
      message: "No se pudieron cargar las variantes del modelo.",
    };
  return {
    ok: true,
    message: "Variantes cargadas.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      modelId: row.fk_modelo_dispositivo_id,
      organizationId: null,
    })),
  };
}

export async function getMotherboardManufacturersAction(
  deviceTypeId: string,
): Promise<MutationResult<CatalogOption[]>> {
  if (!isUuid(deviceTypeId))
    return { ok: false, message: "El tipo de dispositivo no es válido." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("motherboard_model_device_types")
    .select(
      "motherboard_models!inner(motherboard_manufacturers!inner(id,name,is_active))",
    )
    .eq("device_type_id", deviceTypeId)
    .eq("motherboard_models.is_active", true)
    .eq("motherboard_models.motherboard_manufacturers.is_active", true);
  if (error)
    return {
      ok: false,
      message: "No se pudieron cargar los fabricantes de motherboards.",
    };
  const unique = new Map<string, CatalogOption>();
  for (const row of data ?? []) {
    const model = row.motherboard_models as unknown as {
      motherboard_manufacturers: { id: string; name: string };
    };
    const manufacturer = model.motherboard_manufacturers;
    unique.set(manufacturer.id, {
      id: manufacturer.id,
      name: manufacturer.name,
      organizationId: null,
    });
  }
  return {
    ok: true,
    message: "Fabricantes de motherboards cargados.",
    data: [...unique.values()].sort((a, b) =>
      a.name.localeCompare(b.name, "es"),
    ),
  };
}

export async function getMotherboardModelsAction(input: {
  deviceTypeId: string;
  manufacturerId: string;
}): Promise<MutationResult<CatalogOption[]>> {
  if (!isUuid(input.deviceTypeId) || !isUuid(input.manufacturerId))
    return { ok: false, message: "La selección de motherboard no es válida." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("motherboard_model_device_types")
    .select(
      "motherboard_models!inner(id,name,motherboard_manufacturer_id,is_active)",
    )
    .eq("device_type_id", input.deviceTypeId)
    .eq("motherboard_models.motherboard_manufacturer_id", input.manufacturerId)
    .eq("motherboard_models.is_active", true);
  if (error)
    return {
      ok: false,
      message: "No se pudieron cargar los modelos de motherboard.",
    };
  return {
    ok: true,
    message: "Modelos de motherboard cargados.",
    data: (data ?? [])
      .map((row) => {
        const model = row.motherboard_models as unknown as {
          id: string;
          name: string;
          motherboard_manufacturer_id: string;
        };
        return {
          id: model.id,
          name: model.name,
          parentId: model.motherboard_manufacturer_id,
          organizationId: null,
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name, "es")),
  };
}

export async function getCompatibleGpuBrandsAction(
  deviceTypeCode: "desktop_pc" | "notebook",
): Promise<MutationResult<CatalogOption[]>> {
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const supportColumn =
    deviceTypeCode === "desktop_pc"
      ? "desktop_supported"
      : "notebook_supported";
  const { data, error } = await supabase
    .from("gpu_brands")
    .select(`id,name,code,gpu_families!inner(gpu_models!inner(id))`)
    .eq("is_active", true)
    .eq("gpu_families.is_active", true)
    .eq("gpu_families.gpu_models.is_active", true)
    .eq(`gpu_families.gpu_models.${supportColumn}`, true)
    .order("name");
  if (error)
    return {
      ok: false,
      message: "No se pudieron cargar los fabricantes de GPU.",
    };
  return {
    ok: true,
    message: "Fabricantes de GPU cargados.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      code: row.code,
      organizationId: null,
    })),
  };
}

export async function getCompatibleGpuFamiliesAction(
  input: unknown,
): Promise<MutationResult<CatalogOption[]>> {
  const parsed = gpuCatalogFilterSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "El fabricante de GPU no es válido." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const supportColumn =
    parsed.data.deviceTypeCode === "desktop_pc"
      ? "desktop_supported"
      : "notebook_supported";
  const { data, error } = await supabase
    .from("gpu_families")
    .select("id,name,code,fk_gpu_brand_id,gpu_models!inner(id)")
    .eq("fk_gpu_brand_id", parsed.data.id!)
    .eq("is_active", true)
    .eq("gpu_models.is_active", true)
    .eq(`gpu_models.${supportColumn}`, true)
    .order("name");
  if (error)
    return { ok: false, message: "No se pudieron cargar las familias de GPU." };
  return {
    ok: true,
    message: "Familias de GPU cargadas.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      code: row.code,
      parentId: row.fk_gpu_brand_id,
      organizationId: null,
    })),
  };
}

export async function getCompatibleGpuModelsAction(
  input: unknown,
): Promise<MutationResult<CatalogOption[]>> {
  const parsed = gpuCatalogFilterSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "La familia de GPU no es válida." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const supportColumn =
    parsed.data.deviceTypeCode === "desktop_pc"
      ? "desktop_supported"
      : "notebook_supported";
  const { data, error } = await supabase
    .from("gpu_models")
    .select("id,name,code,fk_gpu_family_id")
    .eq("fk_gpu_family_id", parsed.data.id!)
    .eq("is_active", true)
    .eq(supportColumn, true)
    .order("name");
  if (error)
    return { ok: false, message: "No se pudieron cargar los modelos de GPU." };
  return {
    ok: true,
    message: "Modelos de GPU cargados.",
    data: (data ?? []).map((row) => ({
      id: row.id,
      name: row.name,
      code: row.code,
      parentId: row.fk_gpu_family_id,
      organizationId: null,
    })),
  };
}
export async function createCustomBrandAction(
  input: unknown,
): Promise<MutationResult<CatalogOption>> {
  const parsed = customBrandSchema.safeParse(input);
  if (!parsed.success)
    return {
      ok: false,
      message: "Seleccioná primero el tipo y escribí una marca válida.",
    };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .rpc("crear_marca_dispositivo", {
      p_nombre: parsed.data.name,
      p_tipo_dispositivo_id: parsed.data.typeId,
    })
    .single();
  if (error || !data)
    return {
      ok: false,
      message: controlledError(error, "No se pudo registrar la marca."),
    };
  // `device_brands.nombre` was renamed to `name` by the active device-domain
  // contract. Keeping this mapping explicit prevents a newly-created option
  // from being appended to the client selector without a visible label.
  const row = data as {
    id: string;
    name: string;
    fk_organizacion_id: string | null;
  };
  return {
    ok: true,
    message: "Marca registrada correctamente.",
    data: {
      id: row.id,
      name: row.name,
      organizationId: row.fk_organizacion_id,
    },
  };
}
export async function createCustomDeviceModelAction(input: unknown): Promise<
  MutationResult<{
    id: string;
    name: string;
    deviceTypeId: string;
    brandId: string;
    organizationId: string | null;
  }>
> {
  const parsed = customModelSchema.safeParse(input);
  if (!parsed.success)
    return {
      ok: false,
      message: "Seleccioná tipo y marca, e ingresá un modelo válido.",
    };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .rpc("crear_modelo_dispositivo", {
      p_nombre: parsed.data.name,
      p_tipo_dispositivo_id: parsed.data.typeId,
      p_marca_dispositivo_id: parsed.data.brandId,
    })
    .single();
  if (error || !data)
    return {
      ok: false,
      message: controlledError(error, "No se pudo registrar el modelo."),
    };
  const row = data as {
    id: string;
    name: string;
    fk_tipo_dispositivo_id: string;
    fk_marca_dispositivo_id: string;
    fk_organizacion_id: string | null;
  };
  return {
    ok: true,
    message: "Modelo registrado correctamente.",
    data: {
      id: row.id,
      name: row.name,
      deviceTypeId: row.fk_tipo_dispositivo_id,
      brandId: row.fk_marca_dispositivo_id,
      organizationId: row.fk_organizacion_id,
    },
  };
}
export async function createCustomDeviceColorAction(
  input: unknown,
): Promise<
  MutationResult<{ id: string; name: string; organizationId: string | null }>
> {
  const parsed = customColorSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "Ingresá un color válido." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .rpc("crear_color_dispositivo", { p_nombre: parsed.data.name })
    .single();
  if (error || !data)
    return {
      ok: false,
      message: controlledError(error, "No se pudo registrar el color."),
    };
  const row = data as {
    id: string;
    name: string;
    fk_organizacion_id: string | null;
  };
  return {
    ok: true,
    message: "Color registrado correctamente.",
    data: {
      id: row.id,
      name: row.name,
      organizationId: row.fk_organizacion_id,
    },
  };
}

const componentCategoryBySource = {
  hardware_motherboard: "PLACA_MADRE",
  hardware_gpu: "TARJETA_GRAFICA",
  hardware_power_supply: "FUENTE_ALIMENTACION",
  hardware_case: "GABINETE",
  hardware_cpu_cooler: "COOLER_PROCESADOR",
  hardware_wifi: "ADAPTADOR_WIFI",
} as const;

export async function createDynamicCatalogOptionAction(
  input: unknown,
): Promise<MutationResult<CatalogOption>> {
  const parsed = dynamicCatalogSchema.safeParse(input);
  if (!parsed.success)
    return {
      ok: false,
      message: "Revisá el nombre y la selección de catálogo.",
    };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { sourceKey, name, parentId, grandparentId } = parsed.data;
  if (sourceKey === "hardware_processor_model") {
    if (!parentId || !grandparentId)
      return {
        ok: false,
        message: "Seleccioná primero la marca y la familia del procesador.",
      };
    const { data, error } = await supabase
      .rpc("crear_modelo_procesador", {
        p_marca_procesador_id: grandparentId,
        p_familia_procesador_id: parentId,
        p_nombre: name,
      })
      .single();
    if (error || !data)
      return {
        ok: false,
        message: controlledError(error, "No se pudo registrar el procesador."),
      };
    const row = data as {
      id: string;
      nombre: string;
      fk_familia_procesador_id: string;
      fk_organizacion_id: string | null;
    };
    return {
      ok: true,
      message: "Procesador registrado correctamente.",
      data: {
        id: row.id,
        name: row.nombre,
        parentId: row.fk_familia_procesador_id,
        organizationId: row.fk_organizacion_id,
      },
    };
  }
  if (sourceKey === "storage_type" || sourceKey === "accessory") {
    const rpc =
      sourceKey === "storage_type"
        ? "crear_tipo_almacenamiento"
        : "crear_accesorio_dispositivo";
    const { data, error } = await supabase
      .rpc(rpc, { p_nombre: name })
      .single();
    if (error || !data)
      return {
        ok: false,
        message: controlledError(error, "No se pudo registrar la opción."),
      };
    const row = data as {
      id: string;
      nombre: string;
      fk_organizacion_id: string | null;
    };
    return {
      ok: true,
      message: "Opción registrada correctamente.",
      data: {
        id: row.id,
        name: row.nombre,
        organizationId: row.fk_organizacion_id,
      },
    };
  }
  const suffix = sourceKey.endsWith("_brand") ? "_brand" : "_model";
  const categoryKey = sourceKey.slice(
    0,
    -suffix.length,
  ) as keyof typeof componentCategoryBySource;
  const category = componentCategoryBySource[categoryKey];
  if (!category)
    return { ok: false, message: "El catálogo solicitado no está habilitado." };
  if (suffix === "_brand") {
    const { data, error } = await supabase
      .rpc("crear_marca_componente", { p_categoria: category, p_nombre: name })
      .single();
    if (error || !data)
      return {
        ok: false,
        message: controlledError(error, "No se pudo registrar la marca."),
      };
    const row = data as {
      id: string;
      nombre: string;
      fk_organizacion_id: string | null;
    };
    return {
      ok: true,
      message: "Marca registrada correctamente.",
      data: {
        id: row.id,
        name: row.nombre,
        organizationId: row.fk_organizacion_id,
      },
    };
  }
  if (!parentId)
    return {
      ok: false,
      message: "Seleccioná primero la marca del componente.",
    };
  const { data, error } = await supabase
    .rpc("crear_modelo_componente", {
      p_categoria: category,
      p_marca_componente_id: parentId,
      p_nombre: name,
    })
    .single();
  if (error || !data)
    return {
      ok: false,
      message: controlledError(error, "No se pudo registrar el modelo."),
    };
  const row = data as {
    id: string;
    nombre: string;
    fk_marca_componente_id: string;
    fk_organizacion_id: string | null;
  };
  return {
    ok: true,
    message: "Modelo registrado correctamente.",
    data: {
      id: row.id,
      name: row.nombre,
      parentId: row.fk_marca_componente_id,
      organizationId: row.fk_organizacion_id,
    },
  };
}

export async function saveDeviceAction(
  input: unknown,
): Promise<MutationResult<{ id: string }>> {
  const parsed = deviceSchema.safeParse(input);
  if (!parsed.success)
    return {
      ok: false,
      message: "Revisá los datos del dispositivo.",
      fieldErrors: customerFieldErrors(parsed.error),
    };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("save_customer_device_step_two", {
    p_customer_id: parsed.data.customerId,
    p_customer_device_id: parsed.data.deviceId ?? null,
    p_device_type_id: parsed.data.typeId,
    p_device_brand_id: parsed.data.brandId || null,
    p_device_model_id: parsed.data.modelId || null,
    p_serial_number: parsed.data.serialNumber || null,
    p_observations: parsed.data.attributes.equipment_kind || null,
    p_attributes: Object.fromEntries(
      Object.entries(parsed.data.attributes).filter(
        ([key]) =>
          ![
            "mobile_ram_mb",
            "mobile_storage_gb",
            "mobile_sd_present",
            "mobile_sd_capacity_gb",
          ].includes(key),
      ),
    ),
    p_ram_modules: parsed.data.memories,
    p_storage_drives: parsed.data.storageUnits,
    p_ports: parsed.data.ports,
    p_accessory_ids: parsed.data.accessories,
    p_imeis: parsed.data.imeis.map((imei, index) => ({
      imei,
      position: index + 1,
    })),
    p_mobile_specs: {
      ramMb: parsed.data.attributes.mobile_ram_mb ?? "",
      storageGb: parsed.data.attributes.mobile_storage_gb ?? "",
      sdPresent: parsed.data.attributes.mobile_sd_present ?? "false",
      sdCapacityGb: parsed.data.attributes.mobile_sd_capacity_gb ?? "",
    },
  });
  if (error || !data)
    return {
      ok: false,
      message: controlledError(
        error,
        "No se pudieron guardar los datos del dispositivo.",
      ),
    };
  revalidatePath("/repairs/new");
  return {
    ok: true,
    message: "Datos del dispositivo guardados correctamente.",
    data: { id: String(data) },
  };
}

export async function getDeviceStepTwoAction(
  deviceId: string,
): Promise<MutationResult<DeviceStepTwoSnapshot>> {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      deviceId,
    )
  )
    return { ok: false, message: "El dispositivo solicitado no es válido." };
  const { organization } = await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const [
    deviceResult,
    valuesResult,
    ramResult,
    storageResult,
    portsResult,
    accessoriesResult,
    profileResult,
    connectivityResult,
    imeisResult,
    mobileSpecsResult,
  ] = await Promise.all([
    supabase
      .from("customer_devices")
      .select(
        "id,fk_cliente_id,fk_tipo_dispositivo_id,fk_marca_dispositivo_id,fk_modelo_dispositivo_id,fk_variante_modelo_dispositivo_id,fk_color_dispositivo_id,fk_motherboard_model_id,numero_serie,desktop_identity_kind",
      )
      .eq("id", deviceId)
      .eq("fk_organizacion_id", organization.id)
      .maybeSingle(),
    supabase
      .from("customer_device_field_values")
      .select("valor_texto,device_type_fields!inner(device_fields!inner(key))")
      .eq("fk_dispositivo_cliente_id", deviceId),
    supabase
      .from("customer_device_ram_modules")
      .select(
        "fk_ram_type_id,fk_ram_speed_id,capacity_mb,fk_ram_form_factor_id,is_soldered,manufacturer,model",
      )
      .eq("fk_customer_device_id", deviceId)
      .order("created_at"),
    supabase
      .from("customer_device_storage_drives")
      .select(
        "fk_storage_type_id,fk_storage_interface_id,fk_storage_form_factor_id,fk_storage_capacity_id,manufacturer,model,serial_number,condition",
      )
      .eq("fk_customer_device_id", deviceId)
      .order("created_at"),
    supabase
      .from("customer_device_ports")
      .select("fk_port_connector_id,fk_port_protocol_id,quantity,condition")
      .eq("fk_customer_device_id", deviceId)
      .order("id"),
    supabase
      .from("customer_device_accessories")
      .select("fk_accesorio_dispositivo_id")
      .eq("fk_dispositivo_cliente_id", deviceId),
    supabase
      .from("customer_device_hardware_profiles")
      .select(
        "fk_processor_model_id,gpu_brand_id,gpu_family_id,gpu_model_id,fk_display_size_id,fk_display_resolution_id,fk_display_technology_id,fk_display_refresh_rate_id,display_touch,battery_present,battery_functional_status,charger_delivered,charger_condition",
      )
      .eq("fk_customer_device_id", deviceId)
      .maybeSingle(),
    supabase
      .from("customer_device_connectivity")
      .select("fk_connectivity_id")
      .eq("fk_customer_device_id", deviceId),
    supabase
      .from("customer_device_imeis")
      .select("imei,position")
      .eq("fk_customer_device_id", deviceId)
      .order("position"),
    supabase
      .from("customer_device_mobile_specs")
      .select("ram_mb,internal_storage_gb,sd_card_present,sd_card_capacity_gb")
      .eq("fk_customer_device_id", deviceId)
      .maybeSingle(),
  ]);
  const failed = [
    deviceResult,
    valuesResult,
    ramResult,
    storageResult,
    portsResult,
    accessoriesResult,
    profileResult,
    connectivityResult,
    imeisResult,
    mobileSpecsResult,
  ].find((result) => result.error);
  if (failed?.error || !deviceResult.data)
    return {
      ok: false,
      message: controlledError(
        failed?.error ?? null,
        "No se pudieron recuperar los datos del dispositivo.",
      ),
    };
  const row = deviceResult.data;
  const attributes: Record<string, string> = {};
  for (const value of valuesResult.data ?? []) {
    const binding = Array.isArray(value.device_type_fields)
      ? value.device_type_fields[0]
      : value.device_type_fields;
    const field =
      binding &&
      (Array.isArray(binding.device_fields)
        ? binding.device_fields[0]
        : binding.device_fields);
    if (field?.key && value.valor_texto != null)
      attributes[field.key] = value.valor_texto;
  }
  const profile = profileResult.data;
  const mobileSpecs = mobileSpecsResult.data;
  Object.assign(attributes, {
    equipment_kind:
      row.desktop_identity_kind ?? attributes.equipment_kind ?? "",
    variant_id:
      row.fk_variante_modelo_dispositivo_id ?? attributes.variant_id ?? "",
    color_id: row.fk_color_dispositivo_id ?? attributes.color_id ?? "",
    motherboard_model_id:
      row.fk_motherboard_model_id ?? attributes.motherboard_model_id ?? "",
    processor_model_id:
      profile?.fk_processor_model_id ?? attributes.processor_model_id ?? "",
    gpu_brand_id: profile?.gpu_brand_id ?? attributes.gpu_brand_id ?? "",
    gpu_family_id: profile?.gpu_family_id ?? attributes.gpu_family_id ?? "",
    gpu_model_id: profile?.gpu_model_id ?? attributes.gpu_model_id ?? "",
    screen_size: profile?.fk_display_size_id ?? attributes.screen_size ?? "",
    screen_resolution:
      profile?.fk_display_resolution_id ?? attributes.screen_resolution ?? "",
    screen_technology:
      profile?.fk_display_technology_id ?? attributes.screen_technology ?? "",
    screen_refresh_rate:
      profile?.fk_display_refresh_rate_id ??
      attributes.screen_refresh_rate ??
      "",
    screen_touch: String(profile?.display_touch ?? false),
    battery_present: String(profile?.battery_present ?? false),
    battery_status: profile?.battery_functional_status ?? "",
    charger_delivered: String(profile?.charger_delivered ?? false),
    charger_status: profile?.charger_condition ?? "",
    connectivity: JSON.stringify(
      (connectivityResult.data ?? []).map((item) => item.fk_connectivity_id),
    ),
    mobile_ram_mb: mobileSpecs?.ram_mb
      ? String(mobileSpecs.ram_mb)
      : (attributes.mobile_ram_mb ?? ""),
    mobile_storage_gb: mobileSpecs?.internal_storage_gb
      ? String(mobileSpecs.internal_storage_gb)
      : (attributes.mobile_storage_gb ?? ""),
    mobile_sd_present: String(mobileSpecs?.sd_card_present ?? false),
    mobile_sd_capacity_gb: mobileSpecs?.sd_card_capacity_gb
      ? String(mobileSpecs.sd_card_capacity_gb)
      : "",
  });
  return {
    ok: true,
    message: "Datos del dispositivo recuperados correctamente.",
    data: {
      customerId: row.fk_cliente_id,
      device: {
        deviceId: row.id,
        typeId: row.fk_tipo_dispositivo_id,
        attributeGroup: "COMPUTER",
        brandId: row.fk_marca_dispositivo_id ?? "",
        modelId: row.fk_modelo_dispositivo_id ?? "",
        model: "",
        year: "",
        color: "",
        customColor: "",
        serialNumber: row.numero_serie ?? "",
        imei1: "",
        imei2: "",
        imeis: (imeisResult.data ?? []).map((item) => item.imei),
        attributes,
        memories: (ramResult.data ?? []).map((item) => ({
          type: item.fk_ram_type_id,
          speedId: item.fk_ram_speed_id ?? "",
          capacity: String(item.capacity_mb / 1024),
          quantity: "1",
          formFactorId: item.fk_ram_form_factor_id ?? "",
          soldered: item.is_soldered,
          manufacturer: item.manufacturer ?? "",
          model: item.model ?? "",
        })),
        storageUnits: (storageResult.data ?? []).map((item) => ({
          type: item.fk_storage_type_id ?? "",
          interfaceId: item.fk_storage_interface_id ?? "",
          formFactorId: item.fk_storage_form_factor_id ?? "",
          capacity: item.fk_storage_capacity_id ?? "",
          quantity: "1",
          manufacturer: item.manufacturer ?? "",
          model: item.model ?? "",
          serialNumber: item.serial_number ?? "",
          condition: item.condition ?? "",
        })),
        ports: (portsResult.data ?? []).map((item) => ({
          connectorId: item.fk_port_connector_id,
          protocolId: item.fk_port_protocol_id ?? "",
          quantity: String(item.quantity),
          condition: item.condition ?? "",
        })),
        accessories: (accessoriesResult.data ?? []).map(
          (item) => item.fk_accesorio_dispositivo_id,
        ),
      },
    },
  };
}

export async function confirmReceptionAction(
  input: unknown,
): Promise<MutationResult<{ id: string; photoPrefix: string }>> {
  const parsed = receptionSchema.safeParse(input);
  if (!parsed.success)
    return {
      ok: false,
      message: "Revisá la inspección de recepción.",
      fieldErrors: customerFieldErrors(parsed.error),
    };
  const { organization } = await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const databaseInspection = serializeInspection(parsed.data.inspection);
  const { data, error } = await supabase.rpc(
    "confirmar_recepcion_dispositivo",
    {
      p_dispositivo_cliente_id: parsed.data.deviceId,
      p_problema_informado: parsed.data.reportedProblem,
      p_observaciones: parsed.data.observations,
      p_resultados: databaseInspection,
      p_intake_metadata: parsed.data.intakeMetadata,
    },
  );
  if (error || !data)
    return {
      ok: false,
      message: controlledError(error, "No se pudo registrar la recepción."),
    };
  const id = String(data);
  // A reception is evidence of intake. The operational repair starts as its
  // single idempotent ServiceOrder, never as a reception-shaped fake order.
  const { error: orderError } = await supabase.rpc("create_service_order", {
    p_reception_id: id,
    p_priority_id: null,
    p_complexity_id: null,
    p_notes: null,
  });
  if (orderError) {
    return {
      ok: false,
      message:
        "La recepción se registró, pero no se pudo abrir la orden de servicio. Reintentá desde Reparaciones.",
    };
  }
  revalidatePath("/repairs");
  return {
    ok: true,
    message: "Recepción registrada correctamente.",
    data: { id, photoPrefix: `${organization.id}/${id}` },
  };
}

export async function registerReceptionPhotoAction(
  input: unknown,
): Promise<MutationResult<{ id: string }>> {
  const parsed = photoMetadataSchema.safeParse(input);
  if (!parsed.success)
    return { ok: false, message: "No se pudo cargar la fotografía." };
  const { organization } = await requireOwnerOrganization();
  if (
    !parsed.data.storagePath.startsWith(
      `${organization.id}/${parsed.data.receptionId}/`,
    )
  )
    return { ok: false, message: "No se pudo cargar la fotografía." };
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("registrar_foto_recepcion", {
    p_recepcion_dispositivo_id: parsed.data.receptionId,
    p_ruta_storage: parsed.data.storagePath,
    p_descripcion: parsed.data.description || null,
    p_clave_control: parsed.data.inspectionKey || null,
  });
  if (error || !data)
    return { ok: false, message: "No se pudo cargar la fotografía." };
  return {
    ok: true,
    message: "Fotografía agregada correctamente.",
    data: { id: String(data) },
  };
}
