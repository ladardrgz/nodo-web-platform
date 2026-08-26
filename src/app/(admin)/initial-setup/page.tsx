import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { InitialSetupWizard } from "@/features/organizations/components/InitialSetupWizard";
import { buildInitialSetupConfirmationData } from "@/lib/organizations/confirmation";
import { getInitialSetupLocationData } from "@/lib/organizations/geography";
import { getOrganizationLogoSignedUrl } from "@/lib/organizations/logo";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Configuración inicial" };

export default async function InitialSetupPage() {
  const { organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  if (organization.initial_setup_completed) redirect("/dashboard");
  const [logoUrl, locationData] = await Promise.all([
    getOrganizationLogoSignedUrl(organization.logo_path),
    getInitialSetupLocationData(organization.id),
  ]);

  const confirmationData = buildInitialSetupConfirmationData(organization, locationData);

  return <InitialSetupWizard confirmationData={confirmationData} locationData={locationData} logoUrl={logoUrl} organization={organization} />;
}
