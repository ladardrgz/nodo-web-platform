import { z } from "zod";

const email = z
  .string()
  .trim()
  .min(1, "Ingresá tu correo electrónico.")
  .pipe(z.email("El correo electrónico no tiene un formato válido."))
  .transform((value) => value.toLowerCase());
const strongPassword = z
  .string()
  .min(12, "Usá al menos 12 caracteres.")
  .max(128, "La contraseña es demasiado larga.")
  .regex(/[a-z]/, "Incluí una letra minúscula.")
  .regex(/[A-Z]/, "Incluí una letra mayúscula.")
  .regex(/[0-9]/, "Incluí un número.")
  .regex(/[^A-Za-z0-9]/, "Incluí un símbolo.")
  .refine((value) => !["1234567890", "password", "contraseña", "qwerty123", "admin123", "nodo123456"].includes(value.toLocaleLowerCase("es-AR")), "Elegí una contraseña menos predecible.");
const personName = (label: "nombre" | "apellido") =>
  z
    .string()
    .trim()
    .min(2, `Ingresá tu ${label}.`)
    .max(80, `El ${label} es demasiado largo.`)
    .regex(/^[\p{L}][\p{L}\p{M}' -]*$/u, `Ingresá un ${label} válido.`);

export const loginSchema = z.object({
  email,
  password: z.string().min(1, "Ingresá tu contraseña.").max(128),
});

export const registerSchema = z
  .object({
    firstName: personName("nombre"),
    lastName: personName("apellido"),
    email,
    password: strongPassword,
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: "Las contraseñas no coinciden.",
    path: ["confirmPassword"],
  });

export const forgotPasswordSchema = z.object({ email });

export const passwordChangeSchema = z
  .object({ password: strongPassword, confirmPassword: z.string() })
  .refine((data) => data.password === data.confirmPassword, {
    message: "Las contraseñas no coinciden.",
    path: ["confirmPassword"],
  });

export type AuthFieldErrors = Record<string, string[] | undefined>;

export interface AuthActionState {
  status: "idle" | "error" | "success";
  message?: string;
  fieldErrors?: AuthFieldErrors;
  retryAfterSeconds?: number;
}

export const initialAuthActionState: AuthActionState = { status: "idle" };
