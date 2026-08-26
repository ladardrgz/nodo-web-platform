import { z } from "zod";

export function normalizeOrganizationName(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function normalizeOrganizationNameForComparison(value: string): string {
  return normalizeOrganizationName(value).toLocaleLowerCase("es");
}

export const organizationNameSchema = z
  .string()
  .transform(normalizeOrganizationName)
  .pipe(
    z
      .string()
      .min(1, "Ingresá el nombre de la organización.")
      .min(2, "El nombre debe tener al menos 2 caracteres.")
      .max(120, "El nombre no puede superar los 120 caracteres.")
      .regex(/^[\p{L}\p{N} _-]+$/u, "El nombre solo puede contener letras, números, espacios, guiones y guiones bajos."),
  );

export const organizationSlugSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1, "Ingresá el identificador de la organización.")
  .min(2, "El identificador debe tener al menos 2 caracteres.")
  .max(80, "El identificador no puede superar los 80 caracteres.")
  .regex(/^[a-z0-9]+(?:[-_][a-z0-9]+)*$/, "El identificador solo puede contener letras, números, guiones y guiones bajos.");

export const createOrganizationSchema = z.object({
  name: organizationNameSchema,
  slug: organizationSlugSchema,
});

export interface OrganizationCreationState {
  status: "idle" | "error" | "success";
  feedback?: {
    title: string;
    description?: string;
    variant?: "success" | "error" | "warning" | "info";
  };
  fieldErrors?: {
    name?: string[];
    slug?: string[];
  };
  submissionId?: string;
}
