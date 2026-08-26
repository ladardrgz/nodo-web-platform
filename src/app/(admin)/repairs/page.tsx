import { Plus } from "lucide-react";
import type { Metadata } from "next";

import { ButtonLink } from "@/components/ui/Button";
import { PageHeader } from "@/components/ui/PageHeader";
import { RepairsExplorer } from "@/features/repairs/components/RepairsExplorer";
import { listOrganizationRepairs } from "@/features/repairs/repository";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Reparaciones" };

export default async function RepairsPage() {
  const { organization } = await requireOwnerOrganization();
  const repairs = await listOrganizationRepairs(organization.id);
  return (
    <div className="space-y-6">
      <PageHeader eyebrow="Operación" title="Reparaciones" description="Buscá órdenes, filtrá por estado y abrí el seguimiento completo de cada equipo." actions={<ButtonLink href="/repairs/new"><Plus className="size-4" />Nueva reparación</ButtonLink>} />
      <RepairsExplorer referenceNow={new Date().toISOString()} repairs={repairs} />
    </div>
  );
}
