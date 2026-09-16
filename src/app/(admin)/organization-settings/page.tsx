import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { DeletionRequestCard } from "@/features/account-deletion/components/DeletionRequestCard";
import { OrganizationSettingsForm } from "@/features/organizations/components/OrganizationSettingsForm";
import { getInitialSetupLocationData } from "@/lib/organizations/geography";
import { getOrganizationLogoSignedUrl } from "@/lib/organizations/logo";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Configuración de la organización" };

export default async function OrganizationSettingsPage() {
  const { context, organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  if (!organization.initial_setup_completed) redirect("/initial-setup");
  const supabase = await createSupabaseServerClient();
  const [logoUrl, locationData, authUser] = await Promise.all([
    getOrganizationLogoSignedUrl(organization.logo_path),
    getInitialSetupLocationData(organization.id),
    supabase.auth.getUser(),
  ]);

  return (
    <div className="space-y-6">
      <PageHeader eyebrow={organization.initial_setup_completed ? "Editar configuración" : "Primeros pasos"} title="Configuración de la organización" description={organization.initial_setup_completed ? "Actualizá los datos fundamentales que identifican a tu negocio en Nodo." : "Completá esta información para habilitar las funciones operativas de Nodo."} />
      <Card className="p-5 sm:p-7"><OrganizationSettingsForm locationData={locationData} logoUrl={logoUrl} organization={organization} personalEmail={context.email} personalPhone={authUser.data.user?.phone ?? null} /></Card>
      {organization.initial_setup_completed ? <Card className="border-warning/30 bg-warning/5 p-5"><DeletionRequestCard subject="ORGANIZATION" /></Card> : null}
    </div>
  );
}
