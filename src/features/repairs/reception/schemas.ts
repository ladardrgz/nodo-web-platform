import { z } from "zod";

const normalizeSpaces = (value: string) => value.trim().replace(/\s+/g, " ");
const personName = (field: "nombre" | "apellido") => z.string().transform(normalizeSpaces)
  .pipe(z.string().min(1, `Ingresá el ${field}.`).min(2, `El ${field} debe tener al menos 2 caracteres.`).max(80).regex(/^[\p{L}\p{M}'’.-]+(?:\s[\p{L}\p{M}'’.-]+)*$/u, `El ${field} contiene caracteres no válidos.`));
const optionalEmail = z.string().trim().toLowerCase().max(254).refine((value) => value === "" || /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value), "Ingresá un correo electrónico válido.");

export const newCustomerSchema = z.object({
  firstName: personName("nombre"), lastName: personName("apellido"),
  phone: z.string().trim().regex(/^\d{10}$/, "El teléfono debe contener 10 dígitos."), email: optionalEmail,
});
export const customCatalogSchema = z.object({ name: z.string().transform(normalizeSpaces).pipe(z.string().min(2).max(80)) });
export const customBrandSchema = customCatalogSchema.extend({ typeId: z.string().uuid() });
export const customModelSchema = customCatalogSchema.extend({ typeId: z.string().uuid(), brandId: z.string().uuid() });
export const customColorSchema = customCatalogSchema;
export const deviceTypeFilterSchema = z.string().uuid();
export const gpuCatalogFilterSchema = z.object({ id: z.string().uuid().optional(), deviceTypeCode: z.enum(["desktop_pc","notebook"]) });
export const deviceModelFilterSchema = z.object({ typeId: z.string().uuid(), brandId: z.string().uuid() });
export const dynamicCatalogSchema = z.object({
  sourceKey: z.enum([
    "hardware_processor_model",
    "hardware_motherboard_brand", "hardware_motherboard_model",
    "hardware_gpu_brand", "hardware_gpu_model",
    "hardware_power_supply_brand", "hardware_power_supply_model",
    "hardware_case_brand", "hardware_case_model",
    "hardware_cpu_cooler_brand", "hardware_cpu_cooler_model",
    "hardware_wifi_brand", "hardware_wifi_model",
    "storage_type", "accessory",
  ]),
  parentId: z.string().uuid().optional(),
  grandparentId: z.string().uuid().optional(),
  name: z.string().transform(normalizeSpaces).pipe(z.string().min(2).max(200)),
});
const shortText = z.string().transform(normalizeSpaces).pipe(z.string().max(120));
const imeiSchema = z.string().transform((value) => value.replace(/[^0-9]/g, "")).pipe(z.string().length(15, "El IMEI debe contener 15 dígitos.").refine((value) => {
  const sum = [...value].reduce((total, char, index) => { const digit = Number(char); if (index % 2 === 0) return total + digit; const doubled = digit * 2; return total + Math.floor(doubled / 10) + doubled % 10; }, 0);
  return sum % 10 === 0;
}, "El dígito verificador del IMEI no es válido."));
export const deviceSchema = z.object({
  customerId: z.string().uuid(), deviceId: z.string().uuid().optional(), typeId: z.string().uuid(), brandId: z.string().uuid().optional().or(z.literal("")), modelId: z.string().uuid().optional().or(z.literal("")),
  model: shortText, year: z.string().trim().max(4),
  color: z.string().uuid().optional().or(z.literal("")), serialNumber: shortText, imei1: z.string().trim().max(20), imei2: z.string().trim().max(20),
  imeis: z.array(imeiSchema).max(10).refine((values) => new Set(values).size === values.length, "No repitas el mismo IMEI."),
  attributes: z.record(z.string(), z.string().max(160)),
  memories: z.array(z.object({ type: z.string().uuid(), capacity: z.string().regex(/^[1-9]\d{0,6}$/), quantity: z.string().regex(/^[1-9]\d{0,2}$/), soldered: z.boolean().optional(), speedId: z.string().uuid().optional().or(z.literal("")), formFactorId: z.string().uuid().optional().or(z.literal("")), manufacturer: z.string().max(120).optional(), model: z.string().max(120).optional() })).max(12),
  storageUnits: z.array(z.object({ type: z.string().uuid(), capacity: z.string().uuid(), quantity: z.string().regex(/^[1-9]\d{0,2}$/), interfaceId: z.string().uuid().optional().or(z.literal("")), formFactorId: z.string().uuid().optional().or(z.literal("")), manufacturer: z.string().max(120).optional(), model: z.string().max(120).optional(), serialNumber: z.string().max(120).optional(), condition: z.string().max(60).optional() })).max(12),
  ports: z.array(z.object({ connectorId: z.string().uuid(), protocolId: z.string().uuid().optional().or(z.literal("")), quantity: z.string().regex(/^[1-9]\d{0,2}$/), condition: z.string().max(60).optional() })).max(40),
  accessories: z.array(z.string().uuid()).max(30),
});
export const inspectionStatusSchema = z.enum(["NO_DAMAGE", "LIGHT_WEAR", "SCRATCHED", "DENTED", "BROKEN", "MISSING", "NOT_WORKING", "NOT_VERIFIABLE", "NOT_APPLICABLE"]);
export const receptionSchema = z.object({
  customerId: z.string().uuid(), deviceId: z.string().uuid(),
  reportedProblem: z.string().transform(normalizeSpaces).pipe(z.string().min(10, "Describí el problema informado con al menos 10 caracteres.").max(2000)),
  observations: z.string().transform(normalizeSpaces).pipe(z.string().max(2000)),
  inspection: z.array(z.object({ key: z.string().regex(/^[a-z0-9_]+$/).max(60), label: z.string().min(2).max(100), status: inspectionStatusSchema, observation: z.string().transform(normalizeSpaces).pipe(z.string().max(500)) })).max(40),
  intakeMetadata: z.object({
    powerState: z.enum(["POWERS_ON","DOES_NOT_POWER_ON","NOT_TESTED",""]),
    imageState: z.enum(["HAS_IMAGE","NO_IMAGE","NOT_TESTED","NOT_APPLICABLE",""]),
    chargeState: z.enum(["CHARGES","INTERMITTENT","DOES_NOT_CHARGE","NOT_TESTED",""]),
    accessAvailable: z.enum(["true","false",""]),
    accessMethod: z.enum(["UNLOCKED","PIN","PATTERN","PASSWORD","BIOMETRIC","OTHER",""]),
    credentialProvided: z.boolean(),
    postState: z.enum(["COMPLETES","DOES_NOT_COMPLETE","UNDETERMINED","NOT_TESTED","NOT_APPLICABLE",""]),
    osBootState: z.enum(["BOOTS","DOES_NOT_BOOT","NOT_TESTED","NO_OS","NOT_APPLICABLE",""]),
    inventoryStatus: z.enum(["COMPLETE","PARTIAL","NOT_PERFORMED",""]),
    powerTestReason: z.string().trim().max(300),
    receptionItems: z.array(z.object({ accessoryId: z.string().uuid().optional().or(z.literal("")), role: z.enum(["ACCESSORY","PERIPHERAL","LOOSE_COMPONENT","OTHER"]), quantity: z.string().regex(/^[1-9]\d{0,2}$/), description: z.string().trim().max(200).optional(), observation: z.string().trim().max(500).optional() })).max(50),
  }),
});
export const photoMetadataSchema = z.object({ receptionId: z.string().uuid(), storagePath: z.string().max(400), description: z.string().trim().max(300), inspectionKey: z.string().max(60) });

export function customerFieldErrors(error: z.ZodError) {
  const flat = error.flatten().fieldErrors as Record<string, string[] | undefined>;
  return Object.fromEntries(Object.entries(flat).map(([key, value]) => [key, value?.[0] ?? "Dato inválido."]));
}
