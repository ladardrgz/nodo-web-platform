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
const shortText = z.string().transform(normalizeSpaces).pipe(z.string().max(120));
export const deviceSchema = z.object({
  customerId: z.string().uuid(), typeId: z.string().uuid(), brandId: z.string().uuid(),
  model: shortText.pipe(z.string().min(2, "Ingresá el modelo del dispositivo.")), year: z.string().trim().max(4),
  color: shortText, serialNumber: shortText, imei1: z.string().trim().max(20), imei2: z.string().trim().max(20),
  attributes: z.record(z.string(), z.string().max(160)),
  memories: z.array(z.object({ type: z.string().max(30), capacity: z.string().max(30) })).max(12),
  storageUnits: z.array(z.object({ type: z.string().max(30), capacity: z.string().max(30) })).max(12),
  accessories: z.array(z.string().transform(normalizeSpaces).pipe(z.string().min(1).max(60))).max(30),
});
export const inspectionStatusSchema = z.enum(["NO_DAMAGE", "LIGHT_WEAR", "SCRATCHED", "DENTED", "BROKEN", "MISSING", "NOT_WORKING", "NOT_VERIFIABLE", "NOT_APPLICABLE"]);
export const receptionSchema = z.object({
  customerId: z.string().uuid(), deviceId: z.string().uuid(),
  reportedProblem: z.string().transform(normalizeSpaces).pipe(z.string().min(10, "Describí el problema informado con al menos 10 caracteres.").max(2000)),
  observations: z.string().transform(normalizeSpaces).pipe(z.string().max(2000)),
  inspection: z.array(z.object({ key: z.string().regex(/^[a-z0-9_]+$/).max(60), label: z.string().min(2).max(100), status: inspectionStatusSchema, observation: z.string().transform(normalizeSpaces).pipe(z.string().max(500)) })).min(1).max(40),
});
export const photoMetadataSchema = z.object({ receptionId: z.string().uuid(), storagePath: z.string().max(400), description: z.string().trim().max(300), inspectionKey: z.string().max(60) });

export function customerFieldErrors(error: z.ZodError) {
  const flat = error.flatten().fieldErrors as Record<string, string[] | undefined>;
  return Object.fromEntries(Object.entries(flat).map(([key, value]) => [key, value?.[0] ?? "Dato inválido."]));
}
