import { Plus } from "lucide-react";
import type { Metadata } from "next";

import { ButtonLink } from "@/components/ui/Button";
import { DemoDataNotice } from "@/components/ui/DemoDataNotice";
import { PageHeader } from "@/components/ui/PageHeader";
import { mockRepairs } from "@/data/mock-repairs";
import { RepairsExplorer } from "@/features/repairs/components/RepairsExplorer";
import { isDemoDataEnabled } from "@/lib/demo";

export const metadata: Metadata = { title: "Reparaciones" };

export default function RepairsPage() {
  const demoEnabled = isDemoDataEnabled();
  return (
    <div className="space-y-6">
      <PageHeader eyebrow="Operación" title="Reparaciones" description="Buscá órdenes, filtrá por estado y abrí el seguimiento completo de cada equipo." actions={<ButtonLink href="/repairs/new"><Plus className="size-4" />Nueva reparación</ButtonLink>} />
      {demoEnabled ? <DemoDataNotice /> : null}
      <RepairsExplorer repairs={demoEnabled ? mockRepairs : []} />
    </div>
  );
}
