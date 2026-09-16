"use client";

import { useState, type Dispatch, type SetStateAction } from "react";
import { ChevronDown, ChevronUp, Wrench } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { DeviceFormSection } from "@/features/repairs/reception/device/DeviceFormSection";
import { DynamicFieldRenderer } from "@/features/repairs/reception/device/DynamicFieldRenderer";
import { MobileImeisField, RamModulesField, StorageDrivesField } from "@/features/repairs/reception/device/RepeatableDeviceFields";
import { DevicePortsField } from "@/features/repairs/reception/device/DevicePortsField";
import { DeviceAccessoriesSection } from "@/features/repairs/reception/device/DeviceAccessoriesSection";
import type { CatalogOption, DeviceDraft, DynamicDeviceSection, ReceptionFormData } from "@/features/repairs/reception/types";
import type { ProcessorCatalogStates, ProcessorFieldKey } from "@/features/repairs/reception/hooks/useDeviceCatalogs";

export function DeviceDynamicForm({ sections, device, catalogs, processorCatalogStates, processorCatalogErrors, deviceTypeName, setDevice, setAttribute }: {
  sections: DynamicDeviceSection[];
  device: DeviceDraft;
  catalogs: ReceptionFormData["fieldCatalogs"];
  processorCatalogStates: ProcessorCatalogStates;
  processorCatalogErrors: Partial<Record<ProcessorFieldKey, string>>;
  deviceTypeName: string;
  setDevice: Dispatch<SetStateAction<DeviceDraft>>;
  setAttribute: (key: string, value: string) => void | Promise<void>;
}) {
  const [inventoryOpen, setInventoryOpen] = useState(deviceTypeName === "Desktop PC" && device.attributes.inventory_status !== "NOT_PERFORMED");
  const bindingKeys = new Map(sections.flatMap((section) => section.fields.map((field) => [field.bindingId, field.key] as const)));
  const renderedSections = sections.filter((section) => !section.key.endsWith("identification")).map((section) => (
    <DeviceFormSection key={section.id} section={section}>
      {section.fields.map((field) => {
        if (field.overrides.component === "ram-modules") return <RamModulesField key={field.bindingId} device={device} setDevice={setDevice} catalogs={catalogs} />;
        if (field.overrides.component === "storage-drives") return <StorageDrivesField key={field.bindingId} device={device} setDevice={setDevice} catalogs={catalogs} />;
        if (field.overrides.component === "device-ports") return <DevicePortsField key={field.bindingId} device={device} setDevice={setDevice} catalogs={catalogs} />;
        if (field.overrides.component === "mobile-imeis") return <MobileImeisField key={field.bindingId} device={device} setDevice={setDevice} />;
        if (field.key === "device_accessories") return <DeviceAccessoriesSection key={field.bindingId} accessories={catalogs.accessory ?? []} device={device} setDevice={setDevice} />;
        const dependency = field.dependencies[0];
        const dependencyKey = field.overrides.dependsOn ?? (dependency ? bindingKeys.get(dependency.parentBindingId) : undefined);
        const disabled = Boolean(dependencyKey && !device.attributes[dependencyKey]);
        const source = field.overrides.catalog ?? field.dataSourceKey ?? "";
        const rawOptions: CatalogOption[] = field.options.length ? field.options.map((item) => ({ id: item.value, name: item.label, organizationId: null })) : catalogs[source] ?? [];
        const parentValue = dependencyKey ? device.attributes[dependencyKey] : undefined;
        const options = rawOptions.filter((option) => (!parentValue || !option.parentId || option.parentId === parentValue) && (!field.overrides.compatibility || !option.categories?.length || option.categories.includes(field.overrides.compatibility)));
        const processorKey = field.key.startsWith("processor_") ? field.key as ProcessorFieldKey : undefined;
        const state = processorKey ? processorCatalogStates[processorKey] : undefined;
        const emptyMessage = processorKey ? `No hay procesadores compatibles con ${deviceTypeName} para esta selección.` : undefined;
        return <DynamicFieldRenderer key={field.bindingId} field={field} value={device.attributes[field.key] ?? ""} options={options} disabled={disabled || state === "loading" || state === "error"} catalogState={state} catalogError={processorKey ? processorCatalogErrors[processorKey] : undefined} emptyMessage={emptyMessage} onChange={(value) => setAttribute(field.key, value)} />;
      })}
    </DeviceFormSection>
  ));
  if (deviceTypeName === "Desktop PC") return <div className="mt-6 space-y-5">
    <section className="rounded-xl border border-line bg-surface-soft p-5">
      <div className="flex flex-wrap items-center justify-between gap-4"><div><h3 className="flex items-center gap-2 font-bold text-primary"><Wrench className="size-5 text-accent" />Inventario de hardware observado</h3><p className="mt-1 text-sm leading-6 text-muted">Abrilo sólo si corresponde. Registrar un componente no afirma que funcione.</p></div><Button onClick={() => { const next=!inventoryOpen; setInventoryOpen(next); setDevice((current) => ({ ...current, attributes: { ...current.attributes, inventory_status: next ? (current.attributes.inventory_status === "COMPLETE" ? "COMPLETE" : "PARTIAL") : "NOT_PERFORMED" } })); }} variant="secondary">{inventoryOpen ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}{inventoryOpen ? "Cerrar inventario" : "Iniciar inventario"}</Button></div>
      {!inventoryOpen ? <p className="mt-4 rounded-lg border border-dashed border-line p-4 text-sm text-muted">Podés continuar sin abrir el gabinete. El inventario quedará como no realizado.</p> : <label className="mt-4 block text-sm font-semibold text-primary">Alcance del inventario<select className="field-control mt-2 max-w-sm" onChange={(event) => setDevice((current) => ({ ...current, attributes: { ...current.attributes, inventory_status: event.target.value } }))} value={device.attributes.inventory_status ?? "PARTIAL"}><option value="PARTIAL">Parcial</option><option value="COMPLETE">Completo</option></select></label>}
    </section>
    {inventoryOpen ? renderedSections : null}
  </div>;
  return (
    <div className="mt-6 space-y-7">
      {sections.filter((section) => !section.key.endsWith("identification")).map((section) => (
        <DeviceFormSection key={section.id} section={section}>
          {section.fields.map((field) => {
            if (field.overrides.component === "ram-modules") return <RamModulesField key={field.bindingId} device={device} setDevice={setDevice} catalogs={catalogs} />;
            if (field.overrides.component === "storage-drives") return <StorageDrivesField key={field.bindingId} device={device} setDevice={setDevice} catalogs={catalogs} />;
            if (field.overrides.component === "device-ports") return <DevicePortsField key={field.bindingId} device={device} setDevice={setDevice} catalogs={catalogs} />;
            if (field.overrides.component === "mobile-imeis") return <MobileImeisField key={field.bindingId} device={device} setDevice={setDevice} />;
            if (field.key === "device_accessories") return <DeviceAccessoriesSection key={field.bindingId} accessories={catalogs.accessory ?? []} device={device} setDevice={setDevice} />;
            const dependency = field.dependencies[0];
            const dependencyKey = field.overrides.dependsOn ?? (dependency ? bindingKeys.get(dependency.parentBindingId) : undefined);
            const disabled = Boolean(dependencyKey && !device.attributes[dependencyKey]);
            const source = field.overrides.catalog ?? field.dataSourceKey ?? "";
            const rawOptions: CatalogOption[] = field.options.length ? field.options.map((item) => ({ id: item.value, name: item.label, organizationId: null })) : catalogs[source] ?? [];
            const parentValue = dependencyKey ? device.attributes[dependencyKey] : undefined;
            const options = rawOptions.filter((option) => (!parentValue || !option.parentId || option.parentId === parentValue) && (!field.overrides.compatibility || !option.categories?.length || option.categories.includes(field.overrides.compatibility)));
            const processorKey = field.key.startsWith("processor_") ? field.key as ProcessorFieldKey : undefined;
            const state = processorKey ? processorCatalogStates[processorKey] : undefined;
            const emptyMessage = processorKey ? `No hay procesadores compatibles con ${deviceTypeName} para esta selección.` : undefined;
            return <DynamicFieldRenderer key={field.bindingId} field={field} value={device.attributes[field.key] ?? ""} options={options} disabled={disabled || state === "loading" || state === "error"} catalogState={state} catalogError={processorKey ? processorCatalogErrors[processorKey] : undefined} emptyMessage={emptyMessage} onChange={(value) => setAttribute(field.key, value)} />;
          })}
        </DeviceFormSection>
      ))}
    </div>
  );
}
