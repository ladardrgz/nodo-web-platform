import type { Metadata } from "next";

import { Card } from "@/components/ui/Card";
import { ButtonLink } from "@/components/ui/Button";
import { PageHeader } from "@/components/ui/PageHeader";
import { NewRepairForm } from "@/features/repairs/components/NewRepairForm";
import { getReceptionFormData } from "@/features/repairs/reception/data";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Nueva reparación" };

export default async function NewRepairPage() {
  const { organization } = await requireOwnerOrganization();
  let initialData;
  try {
    initialData = await getReceptionFormData(organization.id);
  } catch {
    return <div className="space-y-6"><PageHeader eyebrow="Nueva recepción" title="Recepcionar equipo" description="Identificá al cliente, documentá el dispositivo y conservá evidencia objetiva de cómo ingresó al taller." /><Card className="mx-auto max-w-2xl p-6 text-center"><h2 className="text-lg font-bold text-primary">No pudimos preparar el formulario de recepción</h2><p className="mt-2 text-sm leading-6 text-muted">La información necesaria no está disponible temporalmente. Volvé a intentarlo en unos instantes.</p><ButtonLink className="mt-5" href="/repairs">Volver a reparaciones</ButtonLink></Card></div>;
  }
  return <div className="space-y-6"><PageHeader eyebrow="Nueva recepción" title="Recepcionar equipo" description="Identificá al cliente, documentá el dispositivo y conservá evidencia objetiva de cómo ingresó al taller." /><NewRepairForm initialData={initialData} /></div>;
}
