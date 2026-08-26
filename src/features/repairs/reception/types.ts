export type DeviceAttributeGroup =
  | "MOBILE" | "COMPUTER" | "PRINTER" | "DISPLAY" | "NETWORK"
  | "GAMING" | "CAMERA" | "STORAGE" | "AUDIO" | "PERIPHERAL"
  | "POWER" | "COMMERCIAL" | "OTHER";

export interface CatalogOption {
  id: string;
  name: string;
  category?: string;
  attributeGroup?: DeviceAttributeGroup;
  organizationId: string | null;
  categories?: string[];
}

export interface ReceptionCustomer {
  id: string;
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
}

export interface HistoricalSuggestions {
  models: string[];
  processors: string[];
  motherboards: string[];
  gpus: string[];
}

export interface ReceptionFormData {
  customers: ReceptionCustomer[];
  deviceTypes: CatalogOption[];
  brands: CatalogOption[];
  suggestions: HistoricalSuggestions;
}

export interface MemoryModule { type: string; capacity: string }
export interface StorageUnit { type: string; capacity: string }

export interface DeviceDraft {
  typeId: string;
  attributeGroup: DeviceAttributeGroup;
  brandId: string;
  model: string;
  year: string;
  color: string;
  customColor: string;
  serialNumber: string;
  imei1: string;
  imei2: string;
  attributes: Record<string, string>;
  memories: MemoryModule[];
  storageUnits: StorageUnit[];
  accessories: string[];
}

export type InspectionStatus =
  | "NO_DAMAGE" | "LIGHT_WEAR" | "SCRATCHED" | "DENTED" | "BROKEN"
  | "MISSING" | "NOT_WORKING" | "NOT_VERIFIABLE" | "NOT_APPLICABLE";

export interface InspectionItemDraft {
  key: string;
  label: string;
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
