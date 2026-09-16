import type { Metadata } from "next";

import { PageHeader } from "@/components/ui/PageHeader";
import { PricingExplorer } from "@/features/pricing/components/PricingExplorer";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Precios" };

export default async function PricesPage() {
  await requireOwnerOrganization();
  return <div className="space-y-6"><PageHeader eyebrow="Tarifario" title="Precios" description="No hay un catálogo tarifario persistido en el esquema vigente." /><PricingExplorer items={[]} /></div>;
}
