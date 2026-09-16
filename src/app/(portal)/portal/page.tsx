import { Clock3, Smartphone } from "lucide-react";
import type { Metadata } from "next";

import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { DeletionRequestCard } from "@/features/account-deletion/components/DeletionRequestCard";
import { requireRole } from "@/lib/auth/session";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Mi seguimiento" };

export default async function PortalPage() {
  const context = await requireRole(["CUSTOMER"]);
  const supabase = await createSupabaseServerClient();
  const { data: links } = await supabase.from("customer_user_links").select("customer_id").eq("auth_user_id", context.userId);
  const name = context.profile.display_name || [context.profile.first_name, context.profile.last_name].filter(Boolean).join(" ") || "Cliente";
  return <div className="space-y-6"><div><p className="text-xs font-bold uppercase tracking-[0.18em] text-accent">Portal del cliente</p><h1 className="mt-2 text-3xl font-bold text-primary">Hola, {name}</h1><p className="mt-2 text-sm text-muted">Acá vas a ver qué está pasando con cada equipo asociado a tu cuenta.</p></div><section className="grid gap-4 sm:grid-cols-2"><Card className="p-5"><Smartphone className="size-5 text-accent" /><p className="mt-4 text-sm font-semibold text-muted">Perfiles de cliente vinculados</p><strong className="mt-1 block text-3xl text-primary">{links?.length ?? 0}</strong></Card><Card className="p-5"><Clock3 className="size-5 text-accent" /><p className="mt-4 text-sm font-semibold text-muted">Reparaciones visibles</p><strong className="mt-1 block text-3xl text-primary">0</strong></Card></section><Card><EmptyState showIllustration title="Todavía no hay reparaciones vinculadas" description="Cuando el taller asocie una orden a este acceso, vas a ver aquí su estado, última actualización y fecha estimada." /></Card><Card className="border-warning/30 bg-warning/5 p-5"><DeletionRequestCard subject="CUSTOMER_ACCOUNT" /></Card></div>;
}
