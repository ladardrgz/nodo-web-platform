"use client";

import { useState } from "react";
import { Plus } from "lucide-react";

import { Button } from "@/components/ui/Button";
import { createProcessorCatalogAction } from "@/features/superadmin/master-actions";

type Option = { id: string; name: string; parentId?: string };

export function MasterProcessorForm({ brands, families, generations }: { brands: Option[]; families: Option[]; generations: Option[] }) {
  const [brandId, setBrandId] = useState("");
  const [familyId, setFamilyId] = useState("");
  const [generationId, setGenerationId] = useState("");
  const [model, setModel] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const visibleFamilies = families.filter((family) => family.parentId === brandId);
  const visibleGenerations = generations.filter((generation) => generation.parentId === familyId);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setMessage("");
    const form = new FormData(event.currentTarget);
    const result = await createProcessorCatalogAction({ brandId, familyId, generationId, model, socket: form.get("socket"), cores: form.get("cores") || undefined, threads: form.get("threads") || undefined, integratedGpu: form.get("integratedGpu") });
    setBusy(false); setMessage(result.message);
    if (result.ok) { setModel(""); setGenerationId(""); event.currentTarget.reset(); }
  }

  return <form className="grid gap-3 md:grid-cols-2" onSubmit={submit}>
    <select className="field-control" onChange={(event) => { setBrandId(event.target.value); setFamilyId(""); setGenerationId(""); }} required value={brandId}><option value="">Fabricante CPU</option>{brands.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
    <select className="field-control" disabled={!brandId} onChange={(event) => { setFamilyId(event.target.value); setGenerationId(""); }} required value={familyId}><option value="">Familia CPU</option>{visibleFamilies.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
    <select className="field-control" disabled={!familyId} onChange={(event) => setGenerationId(event.target.value)} value={generationId}><option value="">Serie / generación (opcional)</option>{visibleGenerations.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select>
    <input className="field-control" onChange={(event) => setModel(event.target.value)} placeholder="Modelo comercial, ej. Ryzen 5 5600G" required value={model} />
    <input className="field-control" maxLength={80} name="socket" placeholder="Socket, ej. AM4" />
    <div className="grid grid-cols-2 gap-3"><input className="field-control" min="1" name="cores" placeholder="Núcleos" type="number" /><input className="field-control" min="1" name="threads" placeholder="Hilos" type="number" /></div>
    <input className="field-control" maxLength={120} name="integratedGpu" placeholder="Gráfica integrada (opcional)" />
    <div className="md:col-span-2"><Button loading={busy} loadingText="Guardando…" type="submit"><Plus className="size-4" />Agregar procesador global</Button>{message ? <p aria-live="polite" className="mt-2 text-sm text-muted">{message}</p> : null}</div>
  </form>;
}
