"use client";

import type { Dispatch, SetStateAction } from "react";
import type { CatalogOption, DeviceDraft } from "@/features/repairs/reception/types";

export function DeviceAccessoriesSection({ accessories, device, setDevice }: { accessories: CatalogOption[]; device: DeviceDraft; setDevice: Dispatch<SetStateAction<DeviceDraft>> }) {
  return <div className="grid gap-3 sm:grid-cols-2 md:col-span-2">{accessories.length ? accessories.map((item) => <label className="flex min-h-11 items-center gap-3 rounded-lg border border-border px-3 text-sm font-medium" key={item.id}><input checked={device.accessories.includes(item.id)} className="size-4 accent-accent" onChange={() => setDevice((current) => ({ ...current, accessories: current.accessories.includes(item.id) ? current.accessories.filter((id) => id !== item.id) : [...current.accessories, item.id] }))} type="checkbox" />{item.name}</label>) : <p className="text-sm text-muted">No hay accesorios disponibles.</p>}</div>;
}
