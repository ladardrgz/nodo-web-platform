"use client";

import Image from "next/image";
import { CircleHelp, X } from "lucide-react";
import { useEffect, useId, useRef, useState, type Dispatch, type SetStateAction } from "react";
import { FormField } from "@/components/ui/FormField";
import { SearchableSelect } from "@/features/repairs/reception/SearchableSelect";
import type { CatalogOption, DeviceDraft, ReceptionFormData } from "@/features/repairs/reception/types";
import type { WizardErrors } from "@/features/repairs/reception/wizard-types";

export function DeviceIdentificationSection({ types, brands, models, variants, colors, device, errors, setDevice, chooseType, chooseBrand, chooseModel, brandCatalogState, modelCatalogState, variantCatalogState, deviceTypeCode }: {
  types: CatalogOption[];
  brands: CatalogOption[];
  models: ReceptionFormData["deviceModels"];
  variants: ReceptionFormData["deviceVariants"];
  colors: CatalogOption[];
  device: DeviceDraft;
  errors: WizardErrors;
  setDevice: Dispatch<SetStateAction<DeviceDraft>>;
  chooseType: (id: string) => void | Promise<void>;
  chooseBrand: (id: string) => void | Promise<void>;
  chooseModel: (id: string) => void | Promise<void>;
  brandCatalogState: "idle" | "loading" | "ready" | "error";
  modelCatalogState: "idle" | "loading" | "ready" | "error";
  variantCatalogState: "idle" | "loading" | "ready" | "error";
  deviceTypeCode?: string;
}) {
  const typeOptions = types.map((item) => ({ id: item.id, label: item.name }));
  const brandOptions = brands.map((item) => ({ id: item.id, label: item.name }));
  const modelOptions = models.map((item) => ({ id: item.id, label: item.name }));
  const variantOptions = variants.map((item) => ({ id: item.id, label: item.name }));
  const colorOptions = colors.map((item) => ({ id: item.id, label: item.name }));
  const desktopKind = device.attributes.equipment_kind ?? "";
  const isDesktop = deviceTypeCode === "desktop_pc";
  const showsCommercialIdentity = !isDesktop || desktopKind === "OEM";
  const showsIdentificationHelp = deviceTypeCode === "desktop_pc" || deviceTypeCode === "notebook";
  const [helpOpen, setHelpOpen] = useState(false);
  const helpTitleId = useId();
  const helpDescriptionId = useId();
  const helpTrigger = useRef<HTMLButtonElement>(null);
  const helpClose = useRef<HTMLButtonElement>(null);

  const closeHelp = () => {
    setHelpOpen(false);
    window.setTimeout(() => helpTrigger.current?.focus(), 0);
  };

  useEffect(() => {
    if (!helpOpen) return;
    helpClose.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeHelp();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [helpOpen]);

  return (
    <div className="mt-6 grid gap-5 sm:grid-cols-2">
      <SearchableSelect id="deviceType" label="Tipo de dispositivo" value={device.typeId} options={typeOptions} onChange={chooseType} placeholder={types.length ? "Buscar tipo de dispositivo" : "No hay tipos disponibles"} error={errors.typeId} />
      {device.typeId ? <>
      <section aria-labelledby="device-identification-title" className="sm:col-span-2 flex flex-col-reverse gap-4 rounded-xl border border-line bg-surface-soft p-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="max-w-2xl">
          <h2 className="font-semibold text-primary" id="device-identification-title">Identificación del dispositivo</h2>
          <p className="mt-1 text-sm leading-6 text-muted">Registrá la marca, modelo y demás datos identificatorios del equipo. Estos datos permiten diferenciar correctamente el dispositivo recibido y recuperar su información en futuras reparaciones.</p>
        </div>
        <span className="grid size-20 shrink-0 place-items-center self-start rounded-full border border-line bg-white p-2 shadow-sm sm:self-auto"><Image alt="Ilustración de identificación del dispositivo" className="size-full object-contain" height={512} src="/images/device-information-v2.png" width={512} /></span>
      </section>
      {isDesktop ? <div className="sm:col-span-2">
        <FormField error={errors.equipment_kind} htmlFor="desktop-equipment-kind" label="Tipo de PC" required hint="Armada: configuración personalizada. OEM: equipo prearmado con fabricante y modelo. Desconocida: todavía no puede determinarse.">
          <div className="grid gap-3 sm:grid-cols-3" id="desktop-equipment-kind">
            {[["CUSTOM","Armada / Custom","No requiere inventar una marca del equipo."],["OEM","OEM / Prearmada","Tiene fabricante y modelo comercial."],["UNKNOWN","Desconocida","La identidad comercial aún no pudo comprobarse."]].map(([value,label,description]) => <label className={`cursor-pointer rounded-xl border p-4 transition ${desktopKind === value ? "border-accent bg-accent-soft" : "border-line bg-surface hover:border-accent/50"}`} key={value}>
              <span className="flex items-center gap-2 font-semibold text-primary"><input checked={desktopKind === value} className="size-4 accent-accent" name="desktop-equipment-kind" onChange={() => setDevice((current) => ({ ...current, brandId: value === "OEM" ? current.brandId : "", modelId: value === "OEM" ? current.modelId : "", model: value === "OEM" ? current.model : "", attributes: { ...current.attributes, equipment_kind: value, variant_id: value === "OEM" ? current.attributes.variant_id ?? "" : "" } }))} type="radio" value={value} />{label}</span>
              <span className="mt-2 block text-xs leading-5 text-muted">{description}</span>
            </label>)}
          </div>
        </FormField>
      </div> : null}
      {showsCommercialIdentity ? <>
      <div>
        <SearchableSelect id="brand" label="Marca" value={device.brandId} options={brandOptions} onChange={chooseBrand} disabled={!device.typeId || brandCatalogState === "loading" || brandCatalogState === "error"} placeholder={!device.typeId ? "Primero seleccioná el tipo" : brandCatalogState === "loading" ? "Cargando marcas…" : brandCatalogState === "error" ? "No se pudieron cargar las marcas" : brands.length ? "Buscar marca" : "No hay marcas para este tipo"} error={errors.brandId} />
        {brandCatalogState === "error" ? <p className="mt-2 text-sm text-danger">No se pudieron cargar las marcas. Volvé a seleccionar el tipo.</p> : null}
        <a className="mt-2 inline-flex text-sm font-medium text-accent underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2" href={`/catalogs/device-brands?deviceType=${encodeURIComponent(device.typeId)}`} rel="noopener noreferrer" target="_blank">¿No encontrás la marca? Administrar marcas</a>
      </div>
      <div>
        <SearchableSelect id="model" label="Modelo" value={device.modelId} options={modelOptions} onChange={chooseModel} disabled={!device.brandId || modelCatalogState === "loading" || modelCatalogState === "error"} placeholder={!device.brandId ? "Primero seleccioná tipo y marca" : modelCatalogState === "loading" ? "Cargando modelos…" : modelCatalogState === "error" ? "No se pudieron cargar los modelos" : models.length ? "Buscar modelo" : "No hay modelos para esta selección"} error={errors.model} />
        {modelCatalogState === "error" ? <p className="mt-2 text-sm text-danger">No se pudieron cargar los modelos. Volvé a seleccionar la marca.</p> : null}
      </div>
      <SearchableSelect id="deviceVariant" label="Variante" value={device.attributes.variant_id ?? ""} options={variantOptions} onChange={(value) => setDevice((current) => ({ ...current, attributes: { ...current.attributes, variant_id: value } }))} disabled={!device.modelId || variantCatalogState === "loading" || variantCatalogState === "error"} placeholder={!device.modelId ? "Primero seleccioná el modelo" : variantCatalogState === "loading" ? "Cargando variantes…" : variantCatalogState === "error" ? "No se pudieron cargar las variantes" : variants.length ? "Seleccionar variante" : "Sin variantes configuradas"} />
      </> : <div className="sm:col-span-2 rounded-xl border border-accent/25 bg-accent-soft p-4 text-sm text-primary">La marca del gabinete no se usará como marca de la PC. Podés identificar los fabricantes reales al inventariar los componentes.</div>}
      {showsIdentificationHelp ? <div className="sm:col-span-2">
        <button aria-controls="device-identification-help" aria-expanded={helpOpen} className="inline-flex items-center gap-1.5 text-sm font-medium text-accent underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2" onClick={() => setHelpOpen(true)} ref={helpTrigger} type="button">
          <CircleHelp aria-hidden="true" className="size-4" />
          ¿Dónde encuentro esta información?
        </button>
      </div> : null}
      <FormField htmlFor="serialNumber" label="Número de serie">
        <input className="field-control" id="serialNumber" maxLength={120} value={device.serialNumber} onChange={(event) => setDevice((current) => ({ ...current, serialNumber: event.target.value }))} />
      </FormField>
      <SearchableSelect id="deviceColor" label="Color" value={device.attributes.color_id ?? ""} options={colorOptions} onChange={(value) => setDevice((current) => ({ ...current, attributes: { ...current.attributes, color_id: value } }))} placeholder={colorOptions.length ? "Seleccionar color" : "No hay colores disponibles"} />
      </> : null}
      {helpOpen ? <div className="fixed inset-0 z-[90] flex items-start justify-center overflow-y-auto bg-brand-surface/40 px-4 py-8 backdrop-blur-sm sm:py-12" onPointerDown={(event) => { if (event.currentTarget === event.target) closeHelp(); }}>
        <div aria-describedby={helpDescriptionId} aria-labelledby={helpTitleId} aria-modal="true" className="w-full max-w-4xl rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)] sm:p-6" id="device-identification-help" role="dialog">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[.14em] text-accent">Ayuda</p>
              <h2 className="mt-1 text-lg font-bold text-primary" id={helpTitleId}>¿Dónde encuentro la marca y el modelo?</h2>
              <p className="mt-2 text-sm leading-6 text-muted" id={helpDescriptionId}>La imagen muestra dónde identificar estos datos en una Notebook y en una PC de escritorio.</p>
            </div>
            <button aria-label="Cerrar ayuda de identificación" className="grid size-8 shrink-0 place-items-center rounded-lg text-muted hover:bg-surface-soft hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent" onClick={closeHelp} ref={helpClose} type="button"><X aria-hidden="true" className="size-4" /></button>
          </div>
          <div className="mt-5 overflow-hidden rounded-lg border border-line bg-surface-soft">
            <Image alt="Guía visual para encontrar la marca y el modelo en una Notebook o PC de escritorio" className="h-auto w-full object-contain" height={1024} sizes="(max-width: 1024px) calc(100vw - 3rem), 896px" src="/images/device-identification-help.png" width={1536} />
          </div>
        </div>
      </div> : null}
    </div>
  );
}
