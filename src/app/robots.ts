import type { MetadataRoute } from "next";

import { getAppUrl } from "@/lib/supabase/config";

export default function robots(): MetadataRoute.Robots { const baseUrl = getAppUrl(); return { rules: { userAgent: "*", allow: "/", disallow: ["/dashboard", "/superadmin", "/portal", "/repairs", "/customers", "/inventory", "/prices", "/change-password", "/reset-password"] }, sitemap: `${baseUrl}/sitemap.xml` }; }
