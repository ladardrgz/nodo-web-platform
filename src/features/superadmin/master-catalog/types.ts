export type MasterDomain = "general" | "cpu" | "gpu" | "motherboard" | "ram" | "storage" | "reception";

export type MasterOption = {
  id: string;
  name: string;
  parentId?: string | null;
  secondaryParentId?: string | null;
  code?: string | null;
  active?: boolean;
};

export type MasterRow = {
  id: string;
  entity: string;
  primary: string;
  secondary: string;
  tertiary?: string;
  active: boolean;
  notebook?: boolean;
  desktop?: boolean;
};

export type CatalogHealth = {
  type: { id: string; name: string; code: string };
  counts: Record<string, number>;
  warnings: Array<{ domain: string; kind: string; label: string; targetId: string }>;
};

export type MasterCatalogData = {
  domain: MasterDomain;
  deviceType: MasterOption;
  deviceTypes: MasterOption[];
  health: CatalogHealth;
  rows: MasterRow[];
  options: Record<string, MasterOption[]>;
};
