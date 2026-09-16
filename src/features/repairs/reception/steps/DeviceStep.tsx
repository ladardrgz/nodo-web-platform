"use client";

import type { Dispatch, SetStateAction } from "react";
import { DeviceIdentificationSection } from "@/features/repairs/reception/device/DeviceIdentificationSection";
import { DeviceDynamicForm } from "@/features/repairs/reception/device/DeviceDynamicForm";
import type { CatalogOption, DeviceDraft, ReceptionFormData } from "@/features/repairs/reception/types";
import type { WizardErrors } from "@/features/repairs/reception/wizard-types";
import type { ProcessorCatalogStates, ProcessorFieldKey } from "@/features/repairs/reception/hooks/useDeviceCatalogs";

export function DeviceStep({
  types,
  brands,
  models,
  variants,
  device,
  errors,
  setDevice,
  chooseType,
  chooseBrand,
  chooseModel,
  brandCatalogState,
  modelCatalogState,
  variantCatalogState,
  sections,
  fieldCatalogs,
  setDynamicAttribute,
  processorCatalogStates,
  processorCatalogErrors,
  deviceTypeName,
  deviceTypeCode,
}: {
  types: CatalogOption[];
  brands: CatalogOption[];
  models: ReceptionFormData["deviceModels"];
  variants: ReceptionFormData["deviceVariants"];
  device: DeviceDraft;
  errors: WizardErrors;
  setDevice: Dispatch<SetStateAction<DeviceDraft>>;
  chooseType: (id: string) => void | Promise<void>;
  chooseBrand: (id: string) => void | Promise<void>;
  chooseModel: (id: string) => void | Promise<void>;
  brandCatalogState: "idle" | "loading" | "ready" | "error";
  modelCatalogState: "idle" | "loading" | "ready" | "error";
  variantCatalogState: "idle" | "loading" | "ready" | "error";
  sections: ReceptionFormData["formSectionsByType"][string];
  fieldCatalogs: ReceptionFormData["fieldCatalogs"];
  setDynamicAttribute: (key: string, value: string) => void | Promise<void>;
  processorCatalogStates: ProcessorCatalogStates;
  processorCatalogErrors: Partial<Record<ProcessorFieldKey, string>>;
  deviceTypeName: string;
  deviceTypeCode?: string;
}) {
  return (
    <fieldset>
      <legend className="text-xl font-bold text-primary">2. Información del dispositivo</legend>
      <p className="mt-2 text-sm text-muted">Identificá el equipo. Sus componentes se registran por separado.</p>
      <DeviceIdentificationSection types={types} brands={brands} models={models} variants={variants} colors={fieldCatalogs.color ?? []} device={device} errors={errors} setDevice={setDevice} chooseType={chooseType} chooseBrand={chooseBrand} chooseModel={chooseModel} brandCatalogState={brandCatalogState} modelCatalogState={modelCatalogState} variantCatalogState={variantCatalogState} deviceTypeCode={deviceTypeCode} />
      {device.typeId ? <DeviceDynamicForm sections={sections} device={device} catalogs={fieldCatalogs} processorCatalogStates={processorCatalogStates} processorCatalogErrors={processorCatalogErrors} deviceTypeName={deviceTypeName} setDevice={setDevice} setAttribute={setDynamicAttribute} /> : null}
    </fieldset>
  );
}
