export type DeviceAttributeGroup =
  | "MOBILE" | "COMPUTER" | "PRINTER" | "DISPLAY" | "NETWORK"
  | "GAMING" | "CAMERA" | "STORAGE" | "AUDIO" | "PERIPHERAL"
  | "POWER" | "COMMERCIAL" | "OTHER";

export interface CatalogOption {
  id: string;
  name: string;
  /** Stable database identity for business rules; `name` is presentation only. */
  code?: string;
  category?: string;
  attributeGroup?: DeviceAttributeGroup;
  organizationId: string | null;
  categories?: string[];
  deviceTypeIds?: string[];
  lastUsedAt?: string;
  parentId?: string;
  secondaryParentId?: string;
}

/** Modelo base del sistema o creado por una organización. */
export interface DeviceModelOption {
  id: string;
  name: string;
  deviceTypeId: string;
  brandId: string;
  organizationId: string | null;
}
export interface DeviceColorOption { id: string; name: string; organizationId: string | null }
export interface DeviceVariantOption { id: string; name: string; modelId: string; organizationId: string | null }

/**
 * Definición serializable de un campo del motor de formularios. Las opciones
 * estructurales se resuelven por `dataSourceKey`; las simples vienen de la BD.
 */
export interface DynamicDeviceFieldOption { id: string; value: string; label: string }
export interface DynamicDeviceField {
  bindingId: string;
  key: string;
  label: string;
  fieldType: "TEXT" | "NUMBER" | "TEXTAREA" | "SELECT" | "MULTISELECT" | "CHECKBOX" | "RADIO" | "SWITCH" | "REPEATABLE";
  dataSourceKey: "brand" | "family" | "model" | "variant" | "color" | "memory_capacity" | "storage_capacity" | "storage_type" | "operating_system" | "mobile_operator" | "accessory" | "lock_type" | "notebook_keyboard_mount" | "hardware_processor_brand" | "hardware_processor_family" | "hardware_processor_generation" | "hardware_processor_model" | "hardware_motherboard_brand" | "hardware_motherboard_model" | "hardware_gpu_brand" | "hardware_gpu_family" | "hardware_gpu_model" | "hardware_power_supply_brand" | "hardware_power_supply_model" | "hardware_case_brand" | "hardware_case_model" | "hardware_cpu_cooler_brand" | "hardware_cpu_cooler_model" | "hardware_wifi_brand" | "hardware_wifi_model" | null;
  placeholder: string | null;
  helpText: string | null;
  validation: { min_length?: number; max_length?: number; min_value?: number; max_value?: number; regex_pattern?: string };
  required: boolean;
  overrides: {
    component?: "searchable-select" | "text-input" | "checkbox" | "radio-group" | "multi-select" | "ram-modules" | "storage-drives" | "device-ports" | "mobile-imeis";
    dependsOn?: string;
    catalog?: string;
    compatibility?: string;
    fullWidth?: boolean;
  };
  options: DynamicDeviceFieldOption[];
  dependencies: Array<{ parentBindingId: string; operator: "EQUALS" | "NOT_EQUALS" | "IN" | "NOT_EMPTY" | "EMPTY"; expectedValue: unknown }>;
}
export interface DynamicDeviceSection {
  id: string; key: string; title: string; description: string | null; sortOrder: number;
  uiConfig: { container?: "section" | "repeatable-section"; columns?: { base?: 1 | 2; md?: 1 | 2 }; gap?: "sm" | "md" | "lg" };
  fields: DynamicDeviceField[];
}
export interface ReceptionControl { key: string; label: string; applicableWhenAttribute: string | null; critical: boolean }

export interface ReceptionCustomer {
  id: string;
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
}

export interface HistoricalSuggestions {
  models: string[];
}

export interface ReceptionFormData {
  customers: ReceptionCustomer[];
  deviceTypes: CatalogOption[];
  brands: CatalogOption[];
  deviceModels: DeviceModelOption[];
  deviceColors: DeviceColorOption[];
  deviceVariants: DeviceVariantOption[];
  formSectionsByType: Record<string, DynamicDeviceSection[]>;
  receptionControlsByType: Record<string, ReceptionControl[]>;
  fieldCatalogs: Record<string, CatalogOption[]>;
  accessories: CatalogOption[];
  suggestions: HistoricalSuggestions;
}

export interface MemoryModule {
  type: string; capacity: string; quantity: string; soldered?: boolean;
  speedId?: string; formFactorId?: string; manufacturer?: string; model?: string;
}
export interface StorageUnit {
  type: string; capacity: string; quantity: string;
  interfaceId?: string; formFactorId?: string; manufacturer?: string; model?: string; serialNumber?: string; condition?: string;
}
export interface DevicePort { connectorId: string; protocolId?: string; quantity: string; condition?: string }

export interface DeviceDraft {
  deviceId?: string;
  typeId: string;
  attributeGroup: DeviceAttributeGroup;
  brandId: string;
  modelId: string;
  model: string;
  year: string;
  color: string;
  customColor: string;
  serialNumber: string;
  imei1: string;
  imei2: string;
  imeis: string[];
  attributes: Record<string, string>;
  memories: MemoryModule[];
  storageUnits: StorageUnit[];
  accessories: string[];
  ports: DevicePort[];
}

export interface DeviceStepTwoSnapshot { customerId: string; device: DeviceDraft }

export interface IntakeMetadata {
  powerState: "" | "POWERS_ON" | "DOES_NOT_POWER_ON" | "NOT_TESTED";
  imageState: "" | "HAS_IMAGE" | "NO_IMAGE" | "NOT_TESTED" | "NOT_APPLICABLE";
  chargeState: "" | "CHARGES" | "INTERMITTENT" | "DOES_NOT_CHARGE" | "NOT_TESTED";
  accessAvailable: "" | "true" | "false";
  accessMethod: "" | "UNLOCKED" | "PIN" | "PATTERN" | "PASSWORD" | "BIOMETRIC" | "OTHER";
  credentialProvided: boolean;
  postState: "" | "COMPLETES" | "DOES_NOT_COMPLETE" | "UNDETERMINED" | "NOT_TESTED" | "NOT_APPLICABLE";
  osBootState: "" | "BOOTS" | "DOES_NOT_BOOT" | "NOT_TESTED" | "NO_OS" | "NOT_APPLICABLE";
  inventoryStatus: "" | "COMPLETE" | "PARTIAL" | "NOT_PERFORMED";
  powerTestReason: string;
  receptionItems: Array<{ accessoryId?: string; role: "ACCESSORY" | "PERIPHERAL" | "LOOSE_COMPONENT" | "OTHER"; quantity: string; description?: string; observation?: string }>;
}

export type InspectionStatus =
  | "NO_DAMAGE" | "LIGHT_WEAR" | "SCRATCHED" | "DENTED" | "BROKEN"
  | "MISSING" | "NOT_WORKING" | "NOT_VERIFIABLE" | "NOT_APPLICABLE";

export interface InspectionItemDraft {
  key: string;
  label: string;
  critical: boolean;
  status: InspectionStatus | "";
  observation: string;
}

export interface EvidenceDraft {
  id: string;
  file: File;
  previewUrl: string;
  description: string;
  inspectionKey: string;
}

export type MutationResult<T = undefined> =
  | { ok: true; message: string; data: T }
  | { ok: false; message: string; fieldErrors?: Record<string, string> };
