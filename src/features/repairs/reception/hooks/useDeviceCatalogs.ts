"use client";

import { useRef, useState, type Dispatch, type SetStateAction } from "react";
import { getCompatibleGpuBrandsAction, getCompatibleGpuFamiliesAction, getCompatibleGpuModelsAction, getCompatibleProcessorBrandsAction, getCompatibleProcessorFamiliesAction, getCompatibleProcessorGenerationsAction, getCompatibleProcessorModelsAction, getDeviceBrandsAction, getDeviceModelsAction, getDeviceModelVariantsAction, getMotherboardManufacturersAction, getMotherboardModelsAction } from "@/features/repairs/reception/actions";
import type { DeviceDraft, InspectionItemDraft, ReceptionFormData } from "@/features/repairs/reception/types";

type CatalogState = "idle" | "loading" | "ready" | "error";
export type ProcessorFieldKey = "processor_brand_id" | "processor_family_id" | "processor_generation_id" | "processor_model_id";
export type ProcessorCatalogStates = Record<ProcessorFieldKey, CatalogState>;

const initialProcessorStates: ProcessorCatalogStates = {
  processor_brand_id: "idle",
  processor_family_id: "idle",
  processor_generation_id: "idle",
  processor_model_id: "idle",
};

export function useDeviceCatalogs({ initialData, types, setDevice, setInspection, setFieldError }: {
  initialData: ReceptionFormData;
  types: ReceptionFormData["deviceTypes"];
  setDevice: Dispatch<SetStateAction<DeviceDraft>>;
  setInspection: Dispatch<SetStateAction<InspectionItemDraft[]>>;
  setFieldError: (key: string, value?: string) => void;
}) {
  const [brands, setBrands] = useState(initialData.brands);
  const [models, setModels] = useState(initialData.deviceModels);
  const [variants, setVariants] = useState(initialData.deviceVariants);
  const [brandCatalogState, setBrandCatalogState] = useState<CatalogState>("idle");
  const [modelCatalogState, setModelCatalogState] = useState<CatalogState>("idle");
  const [variantCatalogState, setVariantCatalogState] = useState<CatalogState>("idle");
  const [fieldCatalogs, setFieldCatalogs] = useState(initialData.fieldCatalogs);
  const [processorCatalogStates, setProcessorCatalogStates] = useState<ProcessorCatalogStates>(initialProcessorStates);
  const [processorCatalogErrors, setProcessorCatalogErrors] = useState<Partial<Record<ProcessorFieldKey, string>>>({});
  const processorCatalogRequest = useRef(0);
  const gpuCatalogRequest = useRef(0);

  async function chooseType(id: string) {
    const type = types.find((item) => item.id === id);
    const group = type?.attributeGroup ?? "OTHER";
    setDevice((current) => ({ ...current, typeId: id, attributeGroup: group, brandId: "", modelId: "", model: "", attributes: {}, memories: [], storageUnits: [], ports: [], accessories: [], imeis: [] }));
    const configuredControls = initialData.receptionControlsByType[id] ?? [];
    setInspection(configuredControls.map((control) => ({ key: control.key, label: control.label, critical: control.critical, status: "", observation: "" })));
    setFieldError("typeId");
    setBrands([]);
    setModels([]);
    setVariants([]);
    setVariantCatalogState("idle");
    setModelCatalogState("idle");
    if (id) {
      setBrandCatalogState("loading");
      const result = await getDeviceBrandsAction(id);
      if (result.ok) { setBrands(result.data); setBrandCatalogState("ready"); }
      else setBrandCatalogState("error");
    } else setBrandCatalogState("idle");
    const request = ++processorCatalogRequest.current;
    setProcessorCatalogErrors({});
    if (type?.code !== "desktop_pc" && type?.code !== "notebook") {
      setProcessorCatalogStates(initialProcessorStates);
      setFieldCatalogs((current) => ({ ...current, hardware_processor_brand: [], hardware_processor_family: [], hardware_processor_generation: [], hardware_processor_model: [] }));
      return;
    }
    setProcessorCatalogStates({ ...initialProcessorStates, processor_brand_id: "loading" });
    const result = await getCompatibleProcessorBrandsAction(type.code);
    if (request !== processorCatalogRequest.current) return;
    if (!result.ok) {
      setProcessorCatalogStates({ ...initialProcessorStates, processor_brand_id: "error" });
      setProcessorCatalogErrors({ processor_brand_id: result.message });
      setFieldCatalogs((current) => ({ ...current, hardware_processor_brand: [], hardware_processor_family: [], hardware_processor_generation: [], hardware_processor_model: [] }));
      return;
    }
    setProcessorCatalogStates({ ...initialProcessorStates, processor_brand_id: "ready" });
    const [gpuResult, motherboardResult] = await Promise.all([
      getCompatibleGpuBrandsAction(type.code),
      getMotherboardManufacturersAction(id),
    ]);
    setFieldCatalogs((current) => ({ ...current, hardware_processor_brand: result.data, hardware_processor_family: [], hardware_processor_generation: [], hardware_processor_model: [], gpu_brands: gpuResult?.ok ? gpuResult.data : [], gpu_families: [], gpu_models: [], hardware_motherboard_brand: motherboardResult?.ok ? motherboardResult.data : [], hardware_motherboard_model: [] }));
  }

  async function chooseTechnicalField(key: string, value: string, deviceTypeCode: string | undefined, attributes: Record<string, string>) {
    const resets: Record<string, string[]> = {
      processor_brand_id: ["processor_family_id", "processor_generation_id", "processor_model_id"],
      processor_family_id: ["processor_generation_id", "processor_model_id"],
      processor_generation_id: ["processor_model_id"],
      gpu_brand_id: ["gpu_family_id", "gpu_model_id"],
      gpu_family_id: ["gpu_model_id"],
      motherboard_brand_id: ["motherboard_model_id"],
    };
    setDevice((current) => {
      const attributes = { ...current.attributes, [key]: value };
      for (const target of resets[key] ?? []) attributes[target] = "";
      return { ...current, attributes };
    });
    if (key === "gpu_brand_id") {
      setFieldCatalogs((current) => ({ ...current, gpu_families: [], gpu_models: [] }));
      if (!value) return;
      const request = ++gpuCatalogRequest.current;
      if (deviceTypeCode !== "desktop_pc" && deviceTypeCode !== "notebook") return;
      const result = await getCompatibleGpuFamiliesAction({ id: value, deviceTypeCode });
      if (request === gpuCatalogRequest.current && result.ok) setFieldCatalogs((current) => ({ ...current, gpu_families: result.data }));
      return;
    }
    if (key === "gpu_family_id") {
      setFieldCatalogs((current) => ({ ...current, gpu_models: [] }));
      if (!value) return;
      const request = ++gpuCatalogRequest.current;
      if (deviceTypeCode !== "desktop_pc" && deviceTypeCode !== "notebook") return;
      const result = await getCompatibleGpuModelsAction({ id: value, deviceTypeCode });
      if (request === gpuCatalogRequest.current && result.ok) setFieldCatalogs((current) => ({ ...current, gpu_models: result.data }));
      return;
    }
    if (key === "motherboard_brand_id") {
      setFieldCatalogs((current) => ({ ...current, hardware_motherboard_model: [] }));
      if (!value || !deviceTypeCode) return;
      const typeId = types.find((item) => item.code === deviceTypeCode)?.id;
      if (!typeId) return;
      const result = await getMotherboardModelsAction({ deviceTypeId: typeId, manufacturerId: value });
      if (result.ok) setFieldCatalogs((current) => ({ ...current, hardware_motherboard_model: result.data }));
      return;
    }
    if (!key.startsWith("processor_")) return;
    const processorKey = key as ProcessorFieldKey;
    const downstream: Partial<Record<ProcessorFieldKey, ProcessorFieldKey[]>> = {
      processor_brand_id: ["processor_family_id", "processor_generation_id", "processor_model_id"],
      processor_family_id: ["processor_generation_id", "processor_model_id"],
      processor_generation_id: ["processor_model_id"],
    };
    const targetByField: Partial<Record<ProcessorFieldKey, ProcessorFieldKey>> = {
      processor_brand_id: "processor_family_id",
      processor_family_id: "processor_generation_id",
      processor_generation_id: "processor_model_id",
    };
    const sourceByField: Partial<Record<ProcessorFieldKey, string>> = {
      processor_brand_id: "hardware_processor_family",
      processor_family_id: "hardware_processor_generation",
      processor_generation_id: "hardware_processor_model",
    };
    const targets = downstream[processorKey] ?? [];
    if (targets.length) {
      setFieldCatalogs((current) => {
        const next = { ...current };
        for (const target of targets) next[target === "processor_family_id" ? "hardware_processor_family" : target === "processor_generation_id" ? "hardware_processor_generation" : "hardware_processor_model"] = [];
        return next;
      });
      setProcessorCatalogStates((current) => ({ ...current, ...Object.fromEntries(targets.map((target) => [target, "idle"])) }));
      setProcessorCatalogErrors((current) => {
        const next = { ...current };
        for (const target of targets) delete next[target];
        return next;
      });
    }
    const target = targetByField[processorKey];
    if (!target || !deviceTypeCode || !value) return;
    const request = ++processorCatalogRequest.current;
    setProcessorCatalogStates((current) => ({ ...current, [target]: "loading" }));
    const result = key === "processor_brand_id"
      ? await getCompatibleProcessorFamiliesAction({ deviceTypeCode, brandId: value })
      : key === "processor_family_id"
        ? await getCompatibleProcessorGenerationsAction({ deviceTypeCode, brandId: attributes.processor_brand_id, familyId: value })
        : key === "processor_generation_id"
          ? await getCompatibleProcessorModelsAction({ deviceTypeCode, familyId: attributes.processor_family_id, generationId: value })
          : null;
    if (request !== processorCatalogRequest.current || !result) return;
    if (!result.ok) {
      setProcessorCatalogStates((current) => ({ ...current, [target]: "error" }));
      setProcessorCatalogErrors((current) => ({ ...current, [target]: result.message }));
      return;
    }
    setProcessorCatalogStates((current) => ({ ...current, [target]: "ready" }));
    setFieldCatalogs((current) => ({ ...current, [sourceByField[processorKey]!]: result.data }));
  }

  async function chooseBrand(id: string, typeId: string) {
    setDevice((current) => ({ ...current, brandId: id, modelId: "", model: "", attributes: { ...current.attributes, variant_id: "" } }));
    setModels([]);
    setVariants([]);
    setVariantCatalogState("idle");
    setFieldError("brandId");
    if (!id || !typeId) { setModelCatalogState("idle"); return; }
    setModelCatalogState("loading");
    const result = await getDeviceModelsAction({ typeId, brandId: id });
    if (result.ok) { setModels(result.data); setModelCatalogState("ready"); }
    else setModelCatalogState("error");
  }

  async function chooseModel(id: string) {
    const selected = models.find((item) => item.id === id);
    setDevice((current) => ({ ...current, modelId: id, model: selected?.name ?? "", attributes: { ...current.attributes, variant_id: "" } }));
    setVariants([]);
    if (!id) { setVariantCatalogState("idle"); return; }
    setVariantCatalogState("loading");
    const result = await getDeviceModelVariantsAction(id);
    if (result.ok) { setVariants(result.data); setVariantCatalogState("ready"); }
    else setVariantCatalogState("error");
  }

  return { brands, setBrands, models, setModels, variants, brandCatalogState, modelCatalogState, variantCatalogState, fieldCatalogs, setFieldCatalogs, processorCatalogStates, processorCatalogErrors, chooseType, chooseBrand, chooseModel, chooseTechnicalField };
}
