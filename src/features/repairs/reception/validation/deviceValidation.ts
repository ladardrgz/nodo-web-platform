import type { DeviceDraft } from "@/features/repairs/reception/types";
import type { WizardErrors } from "@/features/repairs/reception/wizard-types";

export function validateDevice(device: DeviceDraft, deviceTypeCode?: string): WizardErrors {
  const errors: WizardErrors = {};
  if (!device.typeId) errors.typeId = "Seleccioná el tipo de dispositivo.";
  const desktopKind = device.attributes.equipment_kind;
  if (deviceTypeCode === "desktop_pc" && !desktopKind) errors.equipment_kind = "Indicá si la PC es armada, OEM o desconocida.";
  const requiresCommercialIdentity = deviceTypeCode !== "desktop_pc" || desktopKind === "OEM";
  if (requiresCommercialIdentity && !device.brandId) errors.brandId = "Seleccioná la marca.";
  if (requiresCommercialIdentity && !device.modelId) errors.model = "Ingresá el modelo del dispositivo.";
  return errors;
}
