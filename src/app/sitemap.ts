import type { MetadataRoute } from "next";

import { getAppUrl } from "@/lib/supabase/config";

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = getAppUrl();
  return ["/", "/terminos", "/privacidad"].map((path) => ({ url: `${baseUrl}${path}`, lastModified: new Date(), changeFrequency: path === "/" ? "weekly" : "monthly", priority: path === "/" ? 1 : 0.6 }));
}
