import "server-only";

export function isDemoDataEnabled(): boolean {
  return process.env.NODE_ENV === "development" || process.env.ENABLE_DEMO_DATA === "true";
}
