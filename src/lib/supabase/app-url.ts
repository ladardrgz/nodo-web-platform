function normalizeAppUrl(value: string): string {
  const withProtocol = /^https?:\/\//i.test(value) ? value : `https://${value}`;
  return withProtocol.replace(/\/$/, "");
}

export function getAppUrl(): string {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL?.trim();
  if (siteUrl) return normalizeAppUrl(siteUrl);

  const productionUrl = process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim();
  if (productionUrl) return normalizeAppUrl(productionUrl);

  const legacyAppUrl = process.env.APP_URL?.trim();
  if (legacyAppUrl) return normalizeAppUrl(legacyAppUrl);

  const vercelUrl = process.env.VERCEL_URL?.trim();
  if (vercelUrl) return normalizeAppUrl(vercelUrl);

  return "http://localhost:3000";
}
