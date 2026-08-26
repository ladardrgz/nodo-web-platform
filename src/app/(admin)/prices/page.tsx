import type { Metadata } from "next";

import { PageHeader } from "@/components/ui/PageHeader";
import { DemoDataNotice } from "@/components/ui/DemoDataNotice";
import { mockPrices } from "@/data/mock-prices";
import { PricingExplorer } from "@/features/pricing/components/PricingExplorer";
import { isDemoDataEnabled } from "@/lib/demo";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Precios" };

export default async function PricesPage() {
  await requireOwnerOrganization();
  const demoEnabled = isDemoDataEnabled();
  return <div className="space-y-6"><PageHeader eyebrow="Tarifario" title="Precios" description="Referencia actual de servicios y productos. Las actualizaciones masivas se implementarán en otra etapa." />{demoEnabled ? <DemoDataNotice /> : null}<PricingExplorer items={demoEnabled ? mockPrices : []} /></div>;
}
