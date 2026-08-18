import { Plus } from "lucide-react";
import type { Metadata } from "next";

import { ButtonLink } from "@/components/ui/Button";
import { DemoDataNotice } from "@/components/ui/DemoDataNotice";
import { PageHeader } from "@/components/ui/PageHeader";
import { mockCustomers } from "@/data/mock-customers";
import { mockRepairs } from "@/data/mock-repairs";
import { CustomersExplorer } from "@/features/customers/components/CustomersExplorer";
import { isDemoDataEnabled } from "@/lib/demo";

export const metadata: Metadata = { title: "Clientes" };

export default function CustomersPage() {
  const demoEnabled = isDemoDataEnabled();
  return (
    <div className="space-y-6">
      <PageHeader eyebrow="Personas y equipos" title="Clientes" description="Consultá información de contacto, dispositivos asociados y reparaciones activas." actions={<ButtonLink href="/repairs/new"><Plus className="size-4" />Nueva reparación</ButtonLink>} />
      {demoEnabled ? <DemoDataNotice /> : null}
      <CustomersExplorer customers={demoEnabled ? mockCustomers : []} repairs={demoEnabled ? mockRepairs : []} />
    </div>
  );
}
