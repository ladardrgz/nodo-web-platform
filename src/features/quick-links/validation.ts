import { z } from "zod";

import { QUICK_LINK_CONFIG, QUICK_LINK_SERVICES, type QuickLinkService } from "./config";

function hostMatches(host: string, allowedHost: string) {
  return host === allowedHost || host.endsWith(`.${allowedHost}`);
}

export function validateQuickLinkUrl(service: QuickLinkService, value: string): string {
  const trimmed = value.trim();
  let url: URL;
  try { url = new URL(trimmed); } catch { throw new Error("Ingresá una URL válida."); }
  if (url.protocol !== "https:") throw new Error("La URL debe comenzar con https://");
  if (url.username || url.password) throw new Error("La URL no puede incluir credenciales.");
  if (!QUICK_LINK_CONFIG[service].hosts.some((host) => hostMatches(url.hostname.toLowerCase(), host))) throw new Error(`La URL no corresponde a ${QUICK_LINK_CONFIG[service].label}.`);
  if (trimmed.length > 2048) throw new Error("La URL es demasiado extensa.");
  return url.toString();
}

export const quickLinkServiceSchema = z.enum(QUICK_LINK_SERVICES);
