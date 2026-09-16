"use client";

import { Plus, Trash2 } from "lucide-react";
import type { Dispatch, SetStateAction } from "react";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { SearchableSelect } from "@/features/repairs/reception/SearchableSelect";
import type { DeviceDraft, ReceptionFormData } from "@/features/repairs/reception/types";

export function DevicePortsField({ device, setDevice, catalogs }: { device: DeviceDraft; setDevice: Dispatch<SetStateAction<DeviceDraft>>; catalogs: ReceptionFormData["fieldCatalogs"] }) {
  const update = (index: number, patch: Partial<DeviceDraft["ports"][number]>) => setDevice((current) => ({ ...current, ports: current.ports.map((item, position) => position === index ? { ...item, ...patch } : item) }));
  return <div className="space-y-4 md:col-span-2">{device.ports.length ? device.ports.map((port, index) => <article className="grid gap-4 rounded-lg border border-border p-4 md:grid-cols-2" key={index}><h4 className="font-bold text-primary md:col-span-2">Puerto {index + 1}</h4><SearchableSelect id={`port-${index}`} label="Conector" value={port.connectorId} options={(catalogs.legacy_port_connector ?? []).map((item) => ({ id: item.id, label: item.name }))} onChange={(connectorId) => update(index, { connectorId })} placeholder="Seleccionar conector" /><FormField htmlFor={`port-quantity-${index}`} label="Cantidad"><input className="field-control" id={`port-quantity-${index}`} min="1" type="number" value={port.quantity} onChange={(event) => update(index, { quantity: event.target.value })} /></FormField><Button aria-label={`Eliminar puerto ${index + 1}`} onClick={() => setDevice((current) => ({ ...current, ports: current.ports.filter((_, position) => position !== index) }))} variant="secondary"><Trash2 className="size-4" />Eliminar</Button></article>) : <p className="text-sm text-muted">Sin puertos cargados.</p>}<Button onClick={() => setDevice((current) => ({ ...current, ports: [...current.ports, { connectorId: "", quantity: "1" }] }))} variant="secondary"><Plus className="size-4" />Agregar puerto</Button></div>;
}
