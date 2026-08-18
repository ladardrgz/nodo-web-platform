import type { Metadata } from "next";

import { PageHeader } from "@/components/ui/PageHeader";
import { mockCustomers } from "@/data/mock-customers";
import { NewRepairForm } from "@/features/repairs/components/NewRepairForm";
import { isDemoDataEnabled } from "@/lib/demo";

export const metadata: Metadata = { title: "Nueva reparación" };

export default function NewRepairPage() {
  return <div className="space-y-6"><PageHeader eyebrow="Nueva recepción" title="Recepcionar equipo" description="Completá cliente, dispositivo y estado inicial. Diagnóstico, presupuesto y fotografías reales se incorporarán en próximos incrementos." /><NewRepairForm customers={isDemoDataEnabled() ? mockCustomers : []} /></div>;
}
