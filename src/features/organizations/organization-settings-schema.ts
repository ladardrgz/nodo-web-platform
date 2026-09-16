import {
  getCountryCallingCode,
  isValidPhoneNumber,
  parsePhoneNumber,
  type CountryCode as Country,
} from "libphonenumber-js/max";
import { z } from "zod";

import { normalizeAddressText, normalizeContactEmail, normalizeOrganizationText } from "./schemas";

const COUNTRY_CODE_PATTERN = /^[A-Z]{2}$/;
const NATIONAL_NUMBER_PATTERN = /^\d{4,15}$/;

export interface NormalizedInternationalPhone {
  countryCode: Country;
  callingCode: string;
  nationalNumber: string;
  number: string;
}

export function normalizeInternationalPhone(countryCode: string, nationalNumber: string): NormalizedInternationalPhone | null {
  const normalizedCountry = countryCode.trim().toUpperCase();
  const normalizedNational = nationalNumber.replace(/\D/gu, "");
  if (!COUNTRY_CODE_PATTERN.test(normalizedCountry) || !NATIONAL_NUMBER_PATTERN.test(normalizedNational)) return null;

  try {
    const country = normalizedCountry as Country;
    const parsed = parsePhoneNumber(normalizedNational, country);
    if (!parsed || parsed.country !== country || !isValidPhoneNumber(normalizedNational, country)) return null;
    if (country === "AR" && normalizedNational.length !== 10) return null;
    return {
      countryCode: country,
      callingCode: `+${getCountryCallingCode(country)}`,
      nationalNumber: parsed.nationalNumber,
      number: parsed.number,
    };
  } catch {
    return null;
  }
}

export interface ParsedStreetAddress {
  street: string;
  streetNumber: number | null;
  withoutNumber: boolean;
}

export function parseStreetAddressLine(value: string): ParsedStreetAddress | null {
  const normalized = normalizeAddressText(value);
  if (!normalized || normalized.length > 140 || /[<>\p{Cc}]/u.test(normalized)) return null;

  const withoutNumber = normalized.match(/^(.+?)\s+(?:s\s*\/\s*n|sin\s+n[uú]mero)$/iu);
  if (withoutNumber) {
    const street = normalizeAddressText(withoutNumber[1]);
    return street.length >= 2 && street.length <= 120 ? { street, streetNumber: null, withoutNumber: true } : null;
  }

  const numbered = normalized.match(/^(.+\S)\s+(\d{1,6})$/u);
  if (!numbered) return null;
  const street = normalizeAddressText(numbered[1]);
  const streetNumber = Number(numbered[2]);
  if (street.length < 2 || street.length > 120 || streetNumber < 1 || streetNumber > 999999) return null;
  return { street, streetNumber, withoutNumber: false };
}

const businessNameSchema = z.string().transform(normalizeOrganizationText).superRefine((value, context) => {
  if (!value) context.addIssue({ code: "custom", message: "Ingresá el nombre del negocio u organización." });
  else if (value.length < 2) context.addIssue({ code: "custom", message: "El nombre debe tener al menos 2 caracteres." });
  else if (value.length > 120) context.addIssue({ code: "custom", message: "El nombre no puede superar los 120 caracteres." });
  else if (/[<>\p{Cc}]/u.test(value)) context.addIssue({ code: "custom", message: "El nombre contiene caracteres no válidos." });
});

const contactEmailSchema = z.string()
  .transform(normalizeContactEmail)
  .pipe(z.string().min(1, "Ingresá el correo electrónico de contacto del negocio.").max(254, "El correo no puede superar los 254 caracteres.").email("Ingresá un correo electrónico válido."));

const geographyId = (message: string) => z.string().trim().min(1, message).max(80, message);

const settingsInput = z.object({
  name: businessNameSchema,
  phoneCountry: z.string().trim().toUpperCase().regex(COUNTRY_CODE_PATTERN, "Seleccioná el país del teléfono."),
  phoneNationalNumber: z.string().transform((value) => value.replace(/\D/gu, "")),
  contactEmail: contactEmailSchema,
  countryId: geographyId("Seleccioná un país."),
  provinceId: geographyId("Seleccioná una provincia o estado."),
  localityId: geographyId("Seleccioná una localidad o ciudad."),
  neighborhoodId: z.string().trim().max(80).transform((value) => value || null),
  addressLine: z.string().transform(normalizeAddressText),
}).strict().superRefine((values, context) => {
  if (!values.phoneNationalNumber) {
    context.addIssue({ code: "custom", path: ["phoneNationalNumber"], message: "Ingresá el teléfono del negocio." });
  } else if (!normalizeInternationalPhone(values.phoneCountry, values.phoneNationalNumber)) {
    context.addIssue({
      code: "custom",
      path: ["phoneNationalNumber"],
      message: values.phoneCountry === "AR"
        ? "Ingresá un número argentino válido de 10 dígitos."
        : "El número no es válido para el país seleccionado.",
    });
  }
  if (!values.addressLine) {
    context.addIssue({ code: "custom", path: ["addressLine"], message: "Ingresá la calle y numeración." });
  } else if (!parseStreetAddressLine(values.addressLine)) {
    context.addIssue({ code: "custom", path: ["addressLine"], message: "Ingresá la calle seguida de la numeración, por ejemplo: Av. 25 de Mayo 1250." });
  }
});

export const organizationSettingsInputSchema = settingsInput.transform((values) => {
  const phone = normalizeInternationalPhone(values.phoneCountry, values.phoneNationalNumber);
  const address = parseStreetAddressLine(values.addressLine);
  if (!phone || !address) throw new Error("INVALID_NORMALIZED_ORGANIZATION_SETTINGS");
  return { ...values, phone, address };
});

export type OrganizationSettingsInput = z.input<typeof organizationSettingsInputSchema>;
export type OrganizationSettingsValues = z.output<typeof organizationSettingsInputSchema>;
