import type { Metadata } from "next";

import { PageHeader } from "@/components/ui/PageHeader";
import { DemoDataNotice } from "@/components/ui/DemoDataNotice";
import { mockInventory } from "@/data/mock-inventory";
import { InventoryExplorer } from "@/features/inventory/components/InventoryExplorer";
import { isDemoDataEnabled } from "@/lib/demo";

export const metadata: Metadata = { title: "Inventario" };

export default function InventoryPage() {
  const demoEnabled = isDemoDataEnabled();
  return <div className="space-y-6"><PageHeader eyebrow="Stock del taller" title="Inventario" description="Consultá existencias y detectá repuestos que requieren atención. Los movimientos se incorporarán más adelante." />{demoEnabled ? <DemoDataNotice /> : null}<InventoryExplorer items={demoEnabled ? mockInventory : []} /></div>;
}
