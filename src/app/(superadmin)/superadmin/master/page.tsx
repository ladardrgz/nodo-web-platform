import type { Metadata } from "next";

import { MasterCatalogConsole } from "@/features/superadmin/components/MasterCatalogConsole";
import { getMasterCatalogData, normalizeMasterDomain } from "@/features/superadmin/master-catalog/data";

export const metadata: Metadata = { title: "Catálogos maestros" };

export default async function MasterCatalogPage({ searchParams }: { searchParams: Promise<{ type?: string; domain?: string; q?: string }> }) {
  const params = await searchParams;
  const data = await getMasterCatalogData({ deviceTypeId: params.type, domain: normalizeMasterDomain(params.domain), search: params.q });
  return <div className="space-y-7">
    <header>
      <p className="text-xs font-bold uppercase tracking-[.16em] text-accent">Administración global</p>
      <h1 className="mt-1 text-3xl font-bold text-primary">Catálogos maestros</h1>
      <p className="mt-2 max-w-3xl text-sm leading-6 text-muted">Gestioná las relaciones que alimentan Nueva Reparación. Las altas y bajas lógicas se validan nuevamente en PostgreSQL y afectan las consultas siguientes sin rebuild.</p>
    </header>
    <MasterCatalogConsole data={data} search={params.q ?? ""} />
  </div>;
}
