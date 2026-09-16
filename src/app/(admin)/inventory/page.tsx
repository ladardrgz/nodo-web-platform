import type { Metadata } from "next";

import { PageHeader } from "@/components/ui/PageHeader";
import { InventoryExplorer } from "@/features/inventory/components/InventoryExplorer";
import { listOrganizationInventory } from "@/features/inventory/repository";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Inventario" };

export default async function InventoryPage() {
  const { organization } = await requireOwnerOrganization();
  const items = await listOrganizationInventory(organization.id);
  return <div className="space-y-6"><PageHeader eyebrow="Stock del taller" title="Inventario" description="Consultá existencias y detectá repuestos que requieren atención." /><InventoryExplorer items={items} /></div>;
}
