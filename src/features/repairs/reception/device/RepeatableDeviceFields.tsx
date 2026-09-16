"use client";

import { Plus, Trash2 } from "lucide-react";
import type { Dispatch, ReactNode, SetStateAction } from "react";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { SearchableSelect } from "@/features/repairs/reception/SearchableSelect";
import type { CatalogOption, DeviceDraft, ReceptionFormData } from "@/features/repairs/reception/types";

type Props = {
  device: DeviceDraft;
  setDevice: Dispatch<SetStateAction<DeviceDraft>>;
  catalogs: ReceptionFormData["fieldCatalogs"];
};

const options = (items: CatalogOption[]) => items.map((item) => ({ id: item.id, label: item.name }));

export function RamModulesField({ device, setDevice, catalogs }: Props) {
  const update = (index: number, patch: Partial<DeviceDraft["memories"][number]>) =>
    setDevice((current) => ({ ...current, memories: current.memories.map((item, position) => position === index ? { ...item, ...patch } : item) }));
  return (
    <RepeatableShell empty="Sin memorias cargadas." addLabel="Agregar módulo" onAdd={() => setDevice((current) => ({ ...current, memories: [...current.memories, { type: "", capacity: "", quantity: "1", soldered: false }] }))}>
      {device.memories.map((item, index) => (
        <article className="grid gap-4 rounded-lg border border-border p-4 md:grid-cols-2" key={index}>
          <h4 className="font-bold text-primary md:col-span-2">Módulo {index + 1}</h4>
          <SearchableSelect id={`ram-type-${index}`} label="Tipo RAM" value={item.type} options={options(catalogs.ram_type ?? [])} onChange={(type) => update(index, { type, speedId: "" })} placeholder="Seleccionar tipo" />
          <FormField htmlFor={`ram-capacity-${index}`} label="Capacidad (GB)"><input className="field-control" id={`ram-capacity-${index}`} min="1" type="number" value={item.capacity} onChange={(event) => update(index, { capacity: event.target.value })} /></FormField>
          <SearchableSelect id={`ram-speed-${index}`} label="Frecuencia" value={item.speedId ?? ""} disabled={!item.type} options={options((catalogs.ram_speed ?? []).filter((entry) => entry.parentId === item.type))} onChange={(speedId) => update(index, { speedId })} placeholder={item.type ? "Seleccionar frecuencia" : "Primero seleccioná el tipo"} />
          <SearchableSelect id={`ram-form-${index}`} label="Factor de forma" value={item.formFactorId ?? ""} options={options(catalogs.ram_form_factor ?? [])} onChange={(formFactorId) => update(index, { formFactorId })} placeholder="Seleccionar factor" />
          <FormField htmlFor={`ram-maker-${index}`} label="Fabricante"><input className="field-control" id={`ram-maker-${index}`} value={item.manufacturer ?? ""} onChange={(event) => update(index, { manufacturer: event.target.value })} /></FormField>
          <FormField htmlFor={`ram-model-${index}`} label="Modelo"><input className="field-control" id={`ram-model-${index}`} value={item.model ?? ""} onChange={(event) => update(index, { model: event.target.value })} /></FormField>
          <label className="flex min-h-11 items-center gap-2 text-sm font-medium"><input checked={item.soldered ?? false} className="size-4 accent-accent" onChange={(event) => update(index, { soldered: event.target.checked })} type="checkbox" />Soldada / onboard</label>
          <Button aria-label={`Eliminar módulo ${index + 1}`} onClick={() => setDevice((current) => ({ ...current, memories: current.memories.filter((_, position) => position !== index) }))} variant="secondary"><Trash2 className="size-4" />Eliminar</Button>
        </article>
      ))}
    </RepeatableShell>
  );
}

export function StorageDrivesField({ device, setDevice, catalogs }: Props) {
  const update = (index: number, patch: Partial<DeviceDraft["storageUnits"][number]>) =>
    setDevice((current) => ({ ...current, storageUnits: current.storageUnits.map((item, position) => position === index ? { ...item, ...patch } : item) }));
  return (
    <RepeatableShell empty="Sin almacenamientos cargados." addLabel="Agregar unidad" onAdd={() => setDevice((current) => ({ ...current, storageUnits: [...current.storageUnits, { type: "", capacity: "", quantity: "1" }] }))}>
      {device.storageUnits.map((item, index) => (
        <article className="grid gap-4 rounded-lg border border-border p-4 md:grid-cols-2" key={index}>
          <h4 className="font-bold text-primary md:col-span-2">Unidad {index + 1}</h4>
          <SearchableSelect id={`storage-type-${index}`} label="Tipo" value={item.type} options={options(catalogs.storage_type ?? [])} onChange={(type) => update(index, { type })} placeholder="Seleccionar tipo" />
          <SearchableSelect id={`storage-interface-${index}`} label="Interfaz" value={item.interfaceId ?? ""} options={options(catalogs.storage_interface ?? [])} onChange={(interfaceId) => update(index, { interfaceId })} placeholder="Seleccionar interfaz" />
          <SearchableSelect id={`storage-form-${index}`} label="Factor de forma" value={item.formFactorId ?? ""} options={options(catalogs.storage_form_factor ?? [])} onChange={(formFactorId) => update(index, { formFactorId })} placeholder="Seleccionar factor" />
          <SearchableSelect id={`storage-capacity-${index}`} label="Capacidad" value={item.capacity} options={options(catalogs.storage_capacity ?? [])} onChange={(capacity) => update(index, { capacity })} placeholder="Seleccionar capacidad" />
          <FormField htmlFor={`storage-maker-${index}`} label="Fabricante"><input className="field-control" id={`storage-maker-${index}`} value={item.manufacturer ?? ""} onChange={(event) => update(index, { manufacturer: event.target.value })} /></FormField>
          <FormField htmlFor={`storage-model-${index}`} label="Modelo"><input className="field-control" id={`storage-model-${index}`} value={item.model ?? ""} onChange={(event) => update(index, { model: event.target.value })} /></FormField>
          <FormField htmlFor={`storage-serial-${index}`} label="Número de serie"><input className="field-control" id={`storage-serial-${index}`} value={item.serialNumber ?? ""} onChange={(event) => update(index, { serialNumber: event.target.value })} /></FormField>
          <FormField htmlFor={`storage-condition-${index}`} label="Estado"><input className="field-control" id={`storage-condition-${index}`} value={item.condition ?? ""} onChange={(event) => update(index, { condition: event.target.value })} /></FormField>
          <Button aria-label={`Eliminar unidad ${index + 1}`} onClick={() => setDevice((current) => ({ ...current, storageUnits: current.storageUnits.filter((_, position) => position !== index) }))} variant="secondary"><Trash2 className="size-4" />Eliminar</Button>
        </article>
      ))}
    </RepeatableShell>
  );
}

export function MobileImeisField({ device, setDevice }: Pick<Props, "device" | "setDevice">) {
  const update = (index: number, value: string) => setDevice((current) => ({ ...current, imeis: current.imeis.map((imei, position) => position === index ? value.replace(/[^0-9]/g, "").slice(0, 15) : imei) }));
  return (
    <RepeatableShell empty="No se registraron IMEIs. Podés continuar si el equipo no enciende o no tiene una etiqueta legible." addLabel="Agregar IMEI" onAdd={() => setDevice((current) => ({ ...current, imeis: [...current.imeis, ""] }))}>
      {device.imeis.map((imei, index) => (
        <article className="grid gap-3 rounded-lg border border-border p-4 sm:grid-cols-[1fr_auto] sm:items-end" key={index}>
          <FormField htmlFor={`mobile-imei-${index}`} label={`IMEI ${index + 1}`} hint="15 dígitos; se valida el dígito verificador."><input className="field-control" id={`mobile-imei-${index}`} inputMode="numeric" maxLength={15} onChange={(event) => update(index, event.target.value)} value={imei} /></FormField>
          <Button aria-label={`Eliminar IMEI ${index + 1}`} onClick={() => setDevice((current) => ({ ...current, imeis: current.imeis.filter((_, position) => position !== index) }))} variant="secondary"><Trash2 className="size-4" />Eliminar</Button>
        </article>
      ))}
    </RepeatableShell>
  );
}

function RepeatableShell({ empty, addLabel, onAdd, children }: { empty: string; addLabel: string; onAdd: () => void; children: ReactNode }) {
  const hasChildren = Array.isArray(children) ? children.length > 0 : Boolean(children);
  return <div className="space-y-4 md:col-span-2">{hasChildren ? children : <p className="text-sm text-muted">{empty}</p>}<Button onClick={onAdd} variant="secondary"><Plus className="size-4" />{addLabel}</Button></div>;
}
