export function normalizeSupabaseUrl(value: string): string {
  const trimmed = value.trim().replace(/\/+$/, "");

  return trimmed.replace(/\/(?:rest|auth)\/v1$/i, "");
}
