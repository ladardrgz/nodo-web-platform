import { createHmac } from "node:crypto";

export type AuthRateLimitAction = "LOGIN" | "REGISTER" | "PASSWORD_RESET" | "RESEND_VERIFICATION" | "OAUTH";

export function createRateLimitKey(secret: string, action: AuthRateLimitAction, dimension: "identifier" | "ip", value: string): string {
  return createHmac("sha256", secret)
    .update(`${action}:${dimension}:${value.trim().toLocaleLowerCase("en")}`)
    .digest("hex");
}
