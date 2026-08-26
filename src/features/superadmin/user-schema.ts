import { z } from "zod";

export function normalizePersonName(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function requiredRoleConfirmation(currentRole: string, nextRole: string): "SUPERADMIN" | "ADMINISTRADOR" | null {
  if (currentRole === nextRole) return null;
  if (nextRole === "SUPERADMIN") return "SUPERADMIN";
  if (nextRole === "OWNER") return "ADMINISTRADOR";
  return null;
}

export const personNameSchema = z
  .string()
  .transform(normalizePersonName)
  .pipe(
    z
      .string()
      .min(1, "Este campo es obligatorio.")
      .min(2, "Debe tener al menos 2 caracteres.")
      .max(80, "No puede superar los 80 caracteres.")
      .regex(/^[\p{L}]+(?:[ '\u2019-][\p{L}]+)*$/u, "Ingresá un nombre válido."),
  );

export const invitationEmailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .min(1, "Ingresá el correo electrónico.")
  .email("Ingresá un correo electrónico válido.");

export const inviteUserSchema = z.object({
  firstName: personNameSchema,
  lastName: personNameSchema,
  email: invitationEmailSchema,
  role: z.enum(["OWNER", "CUSTOMER"], { error: "Seleccione el tipo de usuario." }),
  organizationId: z.uuid("Seleccione la organización a la que pertenecerá."),
});

export interface InvitationState {
  status: "idle" | "error" | "success";
  feedback?: {
    title: string;
    description?: string;
    variant?: "success" | "error" | "warning" | "info";
  };
  fieldErrors?: Partial<Record<"firstName" | "lastName" | "email" | "role" | "organizationId", string[]>>;
  submissionId?: string;
}
