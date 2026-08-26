import { AlertTriangle } from "lucide-react";
import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { OrganizationSettingsForm } from "@/features/organizations/components/OrganizationSettingsForm";
import { getOrganizationLogoSignedUrl } from "@/lib/organizations/logo";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Configuración de la organización" };

export default async function OrganizationSettingsPage() {
  const { organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  if (!organization.initial_setup_completed) redirect("/initial-setup");
  const logoUrl = await getOrganizationLogoSignedUrl(organization.logo_path);

  return (
    <div className="space-y-6">
      <PageHeader eyebrow={organization.initial_setup_completed ? "Editar configuración" : "Primeros pasos"} title="Configuración de la organización" description={organization.initial_setup_completed ? "Actualizá los datos fundamentales que identifican a tu negocio en Nodo." : "Completá esta información para habilitar las funciones operativas de Nodo."} />
      <Card className="p-5 sm:p-7"><OrganizationSettingsForm logoUrl={logoUrl} organization={organization} /></Card>
      {organization.initial_setup_completed ? <Card className="border-warning/30 bg-warning/5 p-5"><div className="flex items-start gap-3"><AlertTriangle className="mt-0.5 size-5 shrink-0 text-warning" /><div><h2 className="font-bold text-primary">Dar de baja la organización</h2><p className="mt-1 text-sm leading-6 text-muted">La baja requiere definir qué sucede con órdenes, clientes, archivos y auditoría. Esta acción está deliberadamente deshabilitada para evitar pérdidas accidentales.</p><button className="mt-4 min-h-10 rounded-lg border border-border px-4 text-sm font-semibold text-muted opacity-60" disabled type="button">Eliminar configuración / dar de baja</button></div></div></Card> : null}
    </div>
  );
}
