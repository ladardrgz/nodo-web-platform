"use server";

import { revalidatePath } from "next/cache";

import { QUICK_LINK_SERVICES, type QuickLinkItem } from "@/features/quick-links/config";
import { validateQuickLinkUrl } from "@/features/quick-links/validation";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export interface QuickLinksActionState {
  status: "idle" | "success" | "error";
  feedback?: { variant: "success" | "error" | "warning"; title: string };
  fieldErrors?: Partial<Record<string, string[]>>;
  submissionId?: string;
}

export async function saveQuickLinksAction(_state: QuickLinksActionState, formData: FormData): Promise<QuickLinksActionState> {
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { data: currentLinks, error: currentLinksError } = await supabase
    .from("user_quick_links")
    .select("service,url,enabled");

  if (currentLinksError) {
    if (process.env.NODE_ENV === "development") {
      console.error("Error técnico al consultar accesos rápidos:", currentLinksError);
    }
    return {
      status: "error",
      feedback: { variant: "error", title: "No pudimos guardar los accesos. Intentá nuevamente." },
    };
  }

  const existingByService = new Map(currentLinks.map((link) => [link.service, link]));
  const links: QuickLinkItem[] = [];
  const fieldErrors: Partial<Record<string, string[]>> = {};
  for (const service of QUICK_LINK_SERVICES) {
    const rawUrl = String(formData.get(`url_${service}`) ?? "").trim();
    if (!rawUrl) {
      const existing = existingByService.get(service);
      if (existing) links.push({ service, url: existing.url, enabled: false });
      continue;
    }
    try {
      links.push({ service, url: validateQuickLinkUrl(service, rawUrl), enabled: formData.get(`enabled_${service}`) === "on" });
    } catch (error) {
      fieldErrors[service] = [error instanceof Error ? error.message : "Ingresá una URL válida."];
    }
  }
  if (Object.keys(fieldErrors).length) return { status: "error", fieldErrors };
  try {
    const { error } = await supabase.rpc("replace_own_quick_links", { p_links: links });
    if (error) throw error;
    revalidatePath("/dashboard", "layout");
    return { status: "success", submissionId: crypto.randomUUID(), feedback: { variant: "success", title: "Accesos rápidos actualizados." } };
  } catch (error) {
    if (process.env.NODE_ENV === "development") console.error("Error técnico al guardar accesos rápidos:", error);
    return { status: "error", feedback: { variant: "error", title: "No pudimos guardar los accesos. Intentá nuevamente." } };
  }
}
