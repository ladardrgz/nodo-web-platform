import { z } from "zod";

import { passwordChangeSchema } from "../auth/schemas";
import type { ActionFeedbackState } from "../../lib/feedback/types";
import { normalizePersonName, personNameSchema } from "./user-schema";

const displayNameSchema = z
  .string()
  .transform((value) => value.trim().replace(/\s+/g, " "))
  .pipe(z.string().min(2, "Ingresá un nombre visible.").max(120, "El nombre visible no puede superar los 120 caracteres.").regex(/^[\p{L}\p{N} ._'\u2019-]+$/u, "Ingresá un nombre visible válido."));

export const superadminProfileSchema = z.object({
  firstName: personNameSchema,
  lastName: personNameSchema,
  displayName: displayNameSchema,
});

export const superadminPasswordSchema = passwordChangeSchema.and(z.object({
  currentPassword: z.string().min(1, "Ingresá tu contraseña actual.").max(128),
}));

export function normalizeProfileValues(values: { firstName: string; lastName: string; displayName: string }) {
  return {
    firstName: normalizePersonName(values.firstName),
    lastName: normalizePersonName(values.lastName),
    displayName: values.displayName.trim().replace(/\s+/g, " "),
  };
}

export interface ProfileActionState extends ActionFeedbackState {
  fieldErrors?: Partial<Record<"firstName" | "lastName" | "displayName" | "currentPassword" | "password" | "confirmPassword", string[]>>;
  submissionId?: string;
}
