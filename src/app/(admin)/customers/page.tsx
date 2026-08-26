import { Plus } from "lucide-react";
import type { Metadata } from "next";

import { ButtonLink } from "@/components/ui/Button";
import { PageHeader } from "@/components/ui/PageHeader";
import { CustomersExplorer } from "@/features/customers/components/CustomersExplorer";
import { listOrganizationCustomers } from "@/features/customers/repository";
import { listOrganizationRepairs } from "@/features/repairs/repository";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Clientes" };

export default async function CustomersPage() {
  const { organization } = await requireOwnerOrganization();
  const [customers, repairs] = await Promise.all([listOrganizationCustomers(organization.id), listOrganizationRepairs(organization.id)]);
  return (
    <div className="space-y-6">
      <PageHeader eyebrow="Personas y equipos" title="Clientes" description="Consultá información de contacto, dispositivos asociados y reparaciones activas." actions={<ButtonLink href="/repairs/new"><Plus className="size-4" />Nueva reparación</ButtonLink>} />
      <CustomersExplorer customers={customers} repairs={repairs} />
    </div>
  );
}
