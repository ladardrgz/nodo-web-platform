"use client";

import { Check, ChevronLeft, ChevronRight, ClipboardCheck, UserRound, Wrench } from "lucide-react";
import Link from "next/link";
import { useMemo, useState, type FormEvent } from "react";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { FormField } from "@/components/ui/FormField";
import type { Customer, DeviceType } from "@/features/customers/types";
import { deviceTypeLabels, getCustomerFullName } from "@/features/customers/types";
import { cn } from "@/lib/cn";

const steps = [
  { id: "customer", label: "Cliente" },
  { id: "device", label: "Dispositivo" },
  { id: "intake", label: "Recepción" },
  { id: "confirm", label: "Confirmación" },
] as const;

interface RepairDraft {
  customerId: string;
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
  deviceType: DeviceType;
  brand: string;
  model: string;
  color: string;
  serialNumber: string;
  accessories: string;
  reportedProblem: string;
  physicalCondition: string;
  intakeNotes: string;
  termsAccepted: boolean;
}

const initialDraft: RepairDraft = {
  customerId: "",
  firstName: "",
  lastName: "",
  phone: "",
  email: "",
  deviceType: "PHONE",
  brand: "",
  model: "",
  color: "",
  serialNumber: "",
  accessories: "",
  reportedProblem: "",
  physicalCondition: "Buen estado general",
  intakeNotes: "",
  termsAccepted: false,
};

export function NewRepairForm({ customers }: { customers: Customer[] }) {
  const [step, setStep] = useState(0);
  const [draft, setDraft] = useState<RepairDraft>(initialDraft);
  const [errors, setErrors] = useState<string[]>([]);
  const [completed, setCompleted] = useState(false);

  const customerName = useMemo(() => `${draft.firstName} ${draft.lastName}`.trim(), [draft.firstName, draft.lastName]);

  function update<K extends keyof RepairDraft>(key: K, value: RepairDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
    setErrors([]);
  }

  function selectCustomer(customerId: string) {
    if (customerId === "NEW") {
      setDraft((current) => ({ ...current, customerId, firstName: "", lastName: "", phone: "", email: "" }));
      return;
    }
    const customer = customers.find((item) => item.id === customerId);
    setDraft((current) => ({
      ...current,
      customerId,
      firstName: customer?.firstName ?? "",
      lastName: customer?.lastName ?? "",
      phone: customer?.phone ?? "",
      email: customer?.email ?? "",
    }));
    setErrors([]);
  }

  function validateCurrentStep(): boolean {
    const nextErrors: string[] = [];
    if (step === 0) {
      if (!draft.customerId) nextErrors.push("Seleccioná un cliente o elegí registrar uno nuevo.");
      if (!draft.firstName.trim() || !draft.lastName.trim()) nextErrors.push("Completá el nombre y apellido del cliente.");
      if (!draft.phone.trim()) nextErrors.push("Ingresá un teléfono de contacto.");
    }
    if (step === 1) {
      if (!draft.brand.trim()) nextErrors.push("Ingresá la marca del dispositivo.");
      if (!draft.model.trim()) nextErrors.push("Ingresá el modelo del dispositivo.");
    }
    if (step === 2) {
      if (!draft.reportedProblem.trim()) nextErrors.push("Describí el problema informado por el cliente.");
      if (!draft.physicalCondition) nextErrors.push("Seleccioná el estado físico general.");
    }
    if (step === 3 && !draft.termsAccepted) nextErrors.push("Confirmá que la información fue revisada con el cliente.");
    setErrors(nextErrors);
    return nextErrors.length === 0;
  }

  function goNext() {
    if (validateCurrentStep()) setStep((current) => Math.min(current + 1, steps.length - 1));
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (validateCurrentStep()) setCompleted(true);
  }

  if (completed) {
    return (
      <Card className="mx-auto max-w-2xl p-6 text-center sm:p-10">
        <span className="mx-auto grid size-16 place-items-center rounded-full bg-emerald-50 text-success"><Check className="size-8" /></span>
        <p className="mt-6 text-xs font-bold uppercase tracking-[0.18em] text-success">Recepción preparada</p>
        <h2 className="mt-2 text-2xl font-bold text-primary">La información quedó validada en modo demostración</h2>
        <p className="mx-auto mt-3 max-w-lg text-sm leading-6 text-muted">Se completó el flujo para {customerName} y su {draft.brand} {draft.model}. No se guardó información porque la persistencia se incorporará con Supabase.</p>
        <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row"><Link className="inline-flex min-h-11 items-center justify-center rounded-lg bg-accent px-5 text-sm font-bold text-white hover:bg-accent-strong" href="/repairs">Volver a reparaciones</Link><button className="inline-flex min-h-11 items-center justify-center rounded-lg border border-border bg-white px-5 text-sm font-bold text-primary hover:bg-slate-50" onClick={() => { setDraft(initialDraft); setStep(0); setCompleted(false); }} type="button">Nueva recepción demo</button></div>
      </Card>
    );
  }

  return (
    <form className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_340px]" onSubmit={handleSubmit}>
      <Card className="overflow-hidden">
        <ol className="grid grid-cols-4 border-b border-border bg-surface-soft">
          {steps.map((item, index) => (
            <li className={cn("relative px-2 py-4 text-center", index < step && "text-success", index === step ? "bg-white text-accent" : "text-muted")} key={item.id}>
              <span className={cn("mx-auto grid size-7 place-items-center rounded-full border text-xs font-bold", index < step ? "border-success bg-success text-white" : index === step ? "border-accent bg-blue-50" : "border-border bg-white")}>
                {index < step ? <Check className="size-4" /> : index + 1}
              </span>
              <span className="mt-2 block text-[11px] font-bold sm:text-xs">{item.label}</span>
            </li>
          ))}
        </ol>

        <div className="p-5 sm:p-7">
          {step === 0 ? <CustomerStep customers={customers} draft={draft} onSelectCustomer={selectCustomer} update={update} /> : null}
          {step === 1 ? <DeviceStep draft={draft} update={update} /> : null}
          {step === 2 ? <IntakeStep draft={draft} update={update} /> : null}
          {step === 3 ? <ConfirmationStep customerName={customerName} draft={draft} update={update} /> : null}

          {errors.length ? <div aria-live="assertive" className="mt-6 rounded-lg border border-red-200 bg-red-50 p-4"><p className="text-sm font-bold text-red-800">Revisá estos datos:</p><ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-red-700">{errors.map((error) => <li key={error}>{error}</li>)}</ul></div> : null}

          <div className="mt-7 flex items-center justify-between border-t border-border pt-5">
            <Button disabled={step === 0} onClick={() => { setErrors([]); setStep((current) => Math.max(0, current - 1)); }} variant="secondary"><ChevronLeft className="size-4" />Anterior</Button>
            {step < steps.length - 1 ? <Button onClick={goNext}>Continuar<ChevronRight className="size-4" /></Button> : <Button type="submit"><ClipboardCheck className="size-4" />Confirmar recepción</Button>}
          </div>
        </div>
      </Card>

      <aside className="self-start xl:sticky xl:top-24">
        <Card className="p-5"><div className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-lg bg-blue-50 text-accent"><Wrench className="size-5" /></span><div><h2 className="font-bold text-primary">Resumen de recepción</h2><p className="text-xs text-muted">Datos todavía no persistidos</p></div></div><dl className="mt-5 space-y-4 text-sm"><SummaryRow label="Cliente" value={customerName || "Sin seleccionar"} /><SummaryRow label="Contacto" value={draft.phone || "Sin completar"} /><SummaryRow label="Dispositivo" value={draft.brand || draft.model ? `${draft.brand} ${draft.model}`.trim() : deviceTypeLabels[draft.deviceType]} /><SummaryRow label="Problema" value={draft.reportedProblem || "Sin completar"} /><SummaryRow label="Estado físico" value={draft.physicalCondition || "Sin completar"} /></dl><div className="mt-5 rounded-lg bg-amber-50 p-3 text-xs leading-5 text-amber-800">La recepción definitiva será inmutable después de confirmarse cuando exista persistencia real.</div></Card>
      </aside>
    </form>
  );
}

type UpdateDraft = <K extends keyof RepairDraft>(key: K, value: RepairDraft[K]) => void;

function CustomerStep({ customers, draft, onSelectCustomer, update }: { customers: Customer[]; draft: RepairDraft; onSelectCustomer: (id: string) => void; update: UpdateDraft }) {
  return <fieldset><legend className="text-xl font-bold text-primary">1. Identificación del cliente</legend><p className="mt-2 text-sm leading-6 text-muted">Buscá un cliente registrado o completá sus datos básicos.</p><div className="mt-6 space-y-5"><FormField htmlFor="customerId" label="Cliente" required><select className="field-control" id="customerId" onChange={(event) => onSelectCustomer(event.target.value)} value={draft.customerId}><option value="">Seleccionar cliente</option>{customers.map((customer) => <option key={customer.id} value={customer.id}>{getCustomerFullName(customer)} · {customer.phone}</option>)}<option value="NEW">+ Registrar nuevo cliente</option></select></FormField><div className="grid gap-4 sm:grid-cols-2"><FormField htmlFor="firstName" label="Nombre" required><input className="field-control" id="firstName" onChange={(event) => update("firstName", event.target.value)} value={draft.firstName} /></FormField><FormField htmlFor="lastName" label="Apellido" required><input className="field-control" id="lastName" onChange={(event) => update("lastName", event.target.value)} value={draft.lastName} /></FormField><FormField htmlFor="phone" label="Teléfono" required><input className="field-control" id="phone" inputMode="tel" onChange={(event) => update("phone", event.target.value)} value={draft.phone} /></FormField><FormField htmlFor="email" label="Correo electrónico"><input className="field-control" id="email" onChange={(event) => update("email", event.target.value)} type="email" value={draft.email} /></FormField></div></div></fieldset>;
}

function DeviceStep({ draft, update }: { draft: RepairDraft; update: UpdateDraft }) {
  return <fieldset><legend className="text-xl font-bold text-primary">2. Datos del dispositivo</legend><p className="mt-2 text-sm leading-6 text-muted">Registrá los datos necesarios para identificar el equipo sin forzar información que no esté disponible.</p><div className="mt-6 grid gap-4 sm:grid-cols-2"><FormField htmlFor="deviceType" label="Tipo" required><select className="field-control" id="deviceType" onChange={(event) => update("deviceType", event.target.value as DeviceType)} value={draft.deviceType}>{Object.entries(deviceTypeLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></FormField><FormField htmlFor="brand" label="Marca" required><input className="field-control" id="brand" onChange={(event) => update("brand", event.target.value)} placeholder="Ej. Samsung" value={draft.brand} /></FormField><FormField htmlFor="model" label="Modelo" required><input className="field-control" id="model" onChange={(event) => update("model", event.target.value)} placeholder="Ej. Galaxy A14" value={draft.model} /></FormField><FormField htmlFor="color" label="Color"><input className="field-control" id="color" onChange={(event) => update("color", event.target.value)} value={draft.color} /></FormField><FormField htmlFor="serialNumber" label="Número de serie"><input className="field-control" id="serialNumber" onChange={(event) => update("serialNumber", event.target.value)} value={draft.serialNumber} /></FormField><FormField htmlFor="accessories" label="Accesorios entregados"><input className="field-control" id="accessories" onChange={(event) => update("accessories", event.target.value)} placeholder="Cargador, funda, cable..." value={draft.accessories} /></FormField></div></fieldset>;
}

function IntakeStep({ draft, update }: { draft: RepairDraft; update: UpdateDraft }) {
  return <fieldset><legend className="text-xl font-bold text-primary">3. Recepción del equipo</legend><p className="mt-2 text-sm leading-6 text-muted">Documentá el problema informado y el estado físico observado al recibirlo.</p><div className="mt-6 space-y-5"><FormField htmlFor="reportedProblem" label="Problema informado" required><textarea className="field-control min-h-28 resize-y" id="reportedProblem" onChange={(event) => update("reportedProblem", event.target.value)} placeholder="Describí con las palabras del cliente qué sucede con el equipo." value={draft.reportedProblem} /></FormField><FormField htmlFor="physicalCondition" label="Estado físico general" required><select className="field-control" id="physicalCondition" onChange={(event) => update("physicalCondition", event.target.value)} value={draft.physicalCondition}><option>Buen estado general</option><option>Rayones visibles</option><option>Golpes visibles</option><option>Pantalla quebrada</option><option>Daño por humedad visible</option><option>No determinado</option></select></FormField><FormField htmlFor="intakeNotes" label="Observaciones de recepción" hint="Las fotografías reales se incorporarán con Supabase Storage en otra fase."><textarea className="field-control min-h-24 resize-y" id="intakeNotes" onChange={(event) => update("intakeNotes", event.target.value)} value={draft.intakeNotes} /></FormField></div></fieldset>;
}

function ConfirmationStep({ customerName, draft, update }: { customerName: string; draft: RepairDraft; update: UpdateDraft }) {
  return <fieldset><legend className="text-xl font-bold text-primary">4. Confirmación</legend><p className="mt-2 text-sm leading-6 text-muted">Revisá la información antes de completar esta demostración de recepción.</p><div className="mt-6 rounded-xl border border-border bg-surface-soft p-5"><div className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-full bg-blue-50 text-accent"><UserRound className="size-5" /></span><div><strong className="text-primary">{customerName}</strong><p className="text-xs text-muted">{draft.phone}{draft.email ? ` · ${draft.email}` : ""}</p></div></div><div className="mt-5 grid gap-4 border-t border-border pt-5 sm:grid-cols-2"><SummaryRow label="Equipo" value={`${draft.brand} ${draft.model}`} /><SummaryRow label="Tipo" value={deviceTypeLabels[draft.deviceType]} /><SummaryRow label="Estado físico" value={draft.physicalCondition} /><SummaryRow label="Accesorios" value={draft.accessories || "Ninguno informado"} /></div><div className="mt-4"><p className="text-xs font-bold uppercase tracking-wide text-muted">Problema informado</p><p className="mt-1 text-sm leading-6 text-primary">{draft.reportedProblem}</p></div></div><label className="mt-5 flex cursor-pointer items-start gap-3 rounded-lg border border-border bg-white p-4"><input checked={draft.termsAccepted} className="mt-0.5 size-5 accent-blue-600" onChange={(event) => update("termsAccepted", event.target.checked)} type="checkbox" /><span className="text-sm leading-6 text-primary">Confirmo que los datos fueron revisados con el cliente. En la etapa con persistencia, esta acción congelará la recepción original.</span></label></fieldset>;
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return <div><dt className="text-xs font-bold uppercase tracking-wide text-muted">{label}</dt><dd className="mt-1 text-sm font-semibold text-primary">{value}</dd></div>;
}
