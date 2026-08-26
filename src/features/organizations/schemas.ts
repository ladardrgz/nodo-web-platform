import { z } from "zod";
import { isValidPhoneNumber, parsePhoneNumber } from "react-phone-number-input";

export const ORGANIZATION_LOGO_MAX_BYTES = 2 * 1024 * 1024;
export const ORGANIZATION_LOGO_ACCEPTED_TYPES = ["image/png", "image/jpeg", "image/webp"] as const;

export function normalizeOrganizationText(value: string): string {
  return value.trim().replace(/\s+/gu, " ");
}

function organizationIdentityField(label: "razón social" | "nombre comercial") {
  return z.string().transform(normalizeOrganizationText).superRefine((value, context) => {
    if (!value) {
      context.addIssue({ code: "custom", message: `Ingresá ${label === "razón social" ? "la" : "el"} ${label}.` });
      return;
    }
    if (value.length < 2) {
      context.addIssue({ code: "custom", message: `${label === "razón social" ? "La" : "El"} ${label} debe tener al menos 2 caracteres.` });
    }
    if (value.length > 120) {
      context.addIssue({ code: "custom", message: `${label === "razón social" ? "La" : "El"} ${label} no puede superar los 120 caracteres.` });
    }
    if (/[<>\p{Cc}]/u.test(value)) {
      context.addIssue({ code: "custom", message: `Revisá los caracteres ingresados en ${label}.` });
    }
  });
}

export const organizationStepOneSchema = z.object({
  legalName: organizationIdentityField("razón social"),
  commercialName: organizationIdentityField("nombre comercial"),
}).strict();

export type OrganizationStepOneValues = z.infer<typeof organizationStepOneSchema>;

export function normalizeContactEmail(value: string): string {
  return value.trim().toLocaleLowerCase("en-US");
}

export function normalizeContactPhone(value: string): string | null {
  const normalized = value.trim();
  if (!normalized) return null;
  try {
    return parsePhoneNumber(normalized)?.number ?? null;
  } catch {
    return null;
  }
}

const contactPhoneSchema = z.string().trim().superRefine((value, context) => {
  if (!value) {
    context.addIssue({ code: "custom", message: "Ingresá un número de teléfono." });
    return;
  }
  const normalized = normalizeContactPhone(value);
  if (!normalized) {
    context.addIssue({ code: "custom", message: "No pudimos interpretar este número de teléfono." });
    return;
  }
  if (!isValidPhoneNumber(normalized)) {
    context.addIssue({ code: "custom", message: "El número ingresado no parece ser válido." });
  }
}).transform((value) => normalizeContactPhone(value) ?? value);

const contactEmailSchema = z.string()
  .transform(normalizeContactEmail)
  .pipe(
    z.string()
      .min(1, "Ingresá el email de contacto.")
      .max(254, "El email de contacto no puede superar los 254 caracteres.")
      .email("Ingresá un email de contacto válido."),
  );

export const organizationStepTwoSchema = z.object({
  phone: contactPhoneSchema,
  contactEmail: contactEmailSchema,
}).strict();

export type OrganizationStepTwoValues = z.infer<typeof organizationStepTwoSchema>;

export function normalizeAddressText(value: string): string {
  return value.trim().replace(/\s+/gu, " ");
}

const requiredGeographyId = (message: string) => z.string().trim().min(1, message).max(80, message);
const optionalAddressText = (max: number, message: string) => z.string()
  .transform(normalizeAddressText)
  .superRefine((value, context) => {
    if (value.length > max || /[<>\p{Cc}]/u.test(value)) context.addIssue({ code: "custom", message });
  })
  .transform((value) => value || null);

export const organizationStepThreeSchema = z.object({
  countryId: requiredGeographyId("Seleccione un país."),
  provinceId: requiredGeographyId("Seleccione una provincia."),
  localityId: requiredGeographyId("Seleccione una localidad."),
  neighborhoodId: z.string().trim().max(80).transform((value) => value || null),
  street: z.string().transform(normalizeAddressText).superRefine((value, context) => {
    if (!value) context.addIssue({ code: "custom", message: "Ingrese la calle." });
    else if (value.length < 2) context.addIssue({ code: "custom", message: "La calle debe tener al menos 2 caracteres." });
    else if (value.length > 120 || /[<>\p{Cc}]/u.test(value)) context.addIssue({ code: "custom", message: "Revisá la calle ingresada." });
  }),
  streetNumber: z.string().trim(),
  withoutNumber: z.boolean(),
  floor: optionalAddressText(10, "El piso no puede superar los 10 caracteres."),
  apartment: optionalAddressText(10, "El departamento no puede superar los 10 caracteres."),
  postalCode: z.string().trim().toUpperCase().superRefine((value, context) => {
    if (value && !/^[A-Z0-9-]{4,10}$/.test(value)) {
      context.addIssue({ code: "custom", message: "Ingresá un código postal válido." });
    }
  }).transform((value) => value || null),
  reference: optionalAddressText(200, "La referencia no puede superar los 200 caracteres."),
}).strict().superRefine((values, context) => {
  if (values.withoutNumber) return;
  if (!values.streetNumber || !/^\d+$/.test(values.streetNumber)) {
    context.addIssue({ code: "custom", path: ["streetNumber"], message: "Ingrese una altura válida." });
    return;
  }
  const number = Number(values.streetNumber);
  if (!Number.isSafeInteger(number) || number < 1 || number > 999999) {
    context.addIssue({ code: "custom", path: ["streetNumber"], message: "Ingrese una altura válida." });
  }
}).transform((values) => ({
  ...values,
  streetNumber: values.withoutNumber ? null : Number(values.streetNumber),
}));

export type OrganizationStepThreeValues = z.infer<typeof organizationStepThreeSchema>;

export function validateOrganizationLogo(file: Pick<File, "size" | "type"> | null): string | null {
  if (!file || file.size === 0) return null;
  if (!ORGANIZATION_LOGO_ACCEPTED_TYPES.includes(file.type as (typeof ORGANIZATION_LOGO_ACCEPTED_TYPES)[number])) {
    return "El formato del logo no es compatible. Usá PNG, JPG o WebP.";
  }
  if (file.size > ORGANIZATION_LOGO_MAX_BYTES) return "El archivo supera el tamaño máximo permitido de 2 MB.";
  return null;
}

const requiredText = (label: string, min: number, max: number) =>
  z.string().trim().min(min, `${label} es obligatorio.`).max(max, `${label} es demasiado extenso.`);

export const organizationSetupSchema = z.object({
  name: requiredText("El nombre de la organización", 2, 120),
  tradeName: requiredText("El nombre comercial", 2, 120),
  phone: requiredText("El teléfono", 6, 30).regex(/^[+()\d\s.-]+$/, "Ingresá un teléfono válido."),
  contactEmail: z.string().trim().min(1, "El email de contacto es obligatorio.").max(254).email("Ingresá un email válido.").toLowerCase(),
  address: requiredText("La dirección", 3, 180),
  locality: requiredText("La localidad", 2, 100),
  province: requiredText("La provincia", 2, 100),
  description: requiredText("La descripción", 10, 600),
});

export type OrganizationSetupValues = z.infer<typeof organizationSetupSchema>;
