export function isGoogleAuthEnabled(): boolean {
  return process.env.ENABLE_GOOGLE_AUTH?.trim().toLowerCase() === "true";
}
