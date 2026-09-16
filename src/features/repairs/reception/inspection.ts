import type { InspectionItemDraft, InspectionStatus } from "./types";

export const INSPECTION_STATUSES: Record<InspectionStatus, { label: string; weight: number | null }> = {
  NO_DAMAGE: { label: "Sin daños", weight: 0 }, LIGHT_WEAR: { label: "Desgaste leve", weight: 0.5 },
  SCRATCHED: { label: "Rayado", weight: 1 }, DENTED: { label: "Golpeado", weight: 2 },
  BROKEN: { label: "Quebrado", weight: 3 }, MISSING: { label: "Faltante", weight: 3 },
  NOT_WORKING: { label: "No funciona", weight: 3 }, NOT_VERIFIABLE: { label: "No verificable", weight: null },
  NOT_APPLICABLE: { label: "No aplica", weight: null },
};

export function calculateCondition(items: InspectionItemDraft[]) {
  const score = items.reduce((sum, item) => sum + (item.status ? (INSPECTION_STATUSES[item.status].weight ?? 0) : 0), 0);
  const label = score === 0 ? "Excelente estado" : score <= 2 ? "Buen estado" : score <= 4 ? "Desgaste normal" : score <= 7 ? "Estado regular" : score <= 12 ? "Dañado" : "Muy dañado";
  const critical = items.filter((item) => item.critical && ["DENTED", "BROKEN", "MISSING", "NOT_WORKING"].includes(item.status));
  return { score, label, critical };
}

export function serializeInspection(items: Array<{ key: string; label: string; status: InspectionStatus; observation: string }>) {
  return items.map(({ status, ...item }) => ({ ...item, condition: status }));
}
