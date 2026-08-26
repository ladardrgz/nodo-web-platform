import type { DeviceAttributeGroup, InspectionItemDraft, InspectionStatus } from "./types";

export const INSPECTION_STATUSES: Record<InspectionStatus, { label: string; weight: number | null }> = {
  NO_DAMAGE: { label: "Sin daños", weight: 0 }, LIGHT_WEAR: { label: "Desgaste leve", weight: 0.5 },
  SCRATCHED: { label: "Rayado", weight: 1 }, DENTED: { label: "Golpeado", weight: 2 },
  BROKEN: { label: "Quebrado", weight: 3 }, MISSING: { label: "Faltante", weight: 3 },
  NOT_WORKING: { label: "No funciona", weight: 3 }, NOT_VERIFIABLE: { label: "No verificable", weight: null },
  NOT_APPLICABLE: { label: "No aplica", weight: null },
};

const common = [["exterior", "Estado exterior general"], ["impact", "Golpes"], ["liquid", "Signos de humedad"], ["prior_opening", "Signos de apertura previa"]] as const;
const lists: Record<DeviceAttributeGroup, readonly (readonly [string, string])[]> = {
  MOBILE: [["screen", "Pantalla"], ["front_glass", "Vidrio frontal"], ["frame", "Marco"], ["back", "Tapa trasera"], ["front_camera", "Cámara frontal"], ["rear_camera", "Cámaras traseras"], ["flash", "Flash"], ["buttons", "Botones físicos"], ["charge_port", "Puerto de carga"], ["speakers", "Parlantes"], ["microphone", "Micrófono"], ["sim_tray", "Bandeja SIM"], ["fingerprint", "Lector de huella"], ["face_id", "Reconocimiento facial"], ["headphone", "Jack de auriculares"], ...common],
  COMPUTER: [["screen", "Pantalla"], ["screen_frame", "Marco de pantalla"], ["hinges", "Bisagras"], ["lid", "Tapa"], ["lower_case", "Carcasa inferior"], ["keyboard", "Teclado"], ["touchpad", "Touchpad"], ["usb", "USB"], ["usb_c", "USB-C"], ["hdmi", "HDMI"], ["audio_jack", "Jack de audio"], ["charge_port", "Puerto de carga"], ["webcam", "Webcam"], ["screws", "Tornillos"], ["rubber_feet", "Patas de goma"], ["charger", "Cargador"], ...common],
  PRINTER: [["case", "Carcasa"], ["paper_tray", "Bandeja de papel"], ["scanner", "Scanner"], ["controls", "Panel de control"], ["rollers", "Rodillos visibles"], ["power", "Encendido"], ...common],
  DISPLAY: [["screen", "Pantalla"], ["frame", "Marco"], ["stand", "Base / soporte"], ["buttons", "Botones"], ["ports", "Puertos"], ...common],
  GAMING: [["case", "Carcasa"], ["ports", "Puertos"], ["controls", "Controles"], ["seals", "Sellos o precintos"], ...common],
  NETWORK: [["case", "Carcasa"], ["antennas", "Antenas"], ["ports", "Puertos"], ["power", "Fuente"], ...common],
  CAMERA: [["lens", "Lente"], ["screen", "Pantalla"], ["case", "Carcasa"], ["ports", "Puertos"], ...common],
  STORAGE: [["case", "Carcasa"], ["connector", "Conector"], ["cable", "Cable"], ...common],
  AUDIO: [["case", "Carcasa"], ["speakers", "Parlantes"], ["controls", "Controles"], ["ports", "Puertos"], ...common],
  PERIPHERAL: [["case", "Carcasa"], ["buttons", "Botones / teclas"], ["cable", "Cable / conector"], ...common],
  POWER: [["case", "Carcasa"], ["cable", "Cable"], ["connectors", "Conectores"], ...common],
  COMMERCIAL: [["case", "Carcasa"], ["screen", "Pantalla"], ["buttons", "Botones"], ["ports", "Puertos"], ...common],
  OTHER: common,
};

export const CRITICAL_ITEM_KEYS = new Set(["screen", "hinges", "charge_port", "liquid", "battery", "seals", "screws", "prior_opening"]);
export function createInspection(group: DeviceAttributeGroup): InspectionItemDraft[] { return lists[group].map(([key, label]) => ({ key, label, status: "", observation: "" })); }
export function calculateCondition(items: InspectionItemDraft[]) {
  const score = items.reduce((sum, item) => sum + (item.status ? (INSPECTION_STATUSES[item.status].weight ?? 0) : 0), 0);
  const label = score === 0 ? "Excelente estado" : score <= 2 ? "Buen estado" : score <= 4 ? "Desgaste normal" : score <= 7 ? "Estado regular" : score <= 12 ? "Dañado" : "Muy dañado";
  const critical = items.filter((item) => CRITICAL_ITEM_KEYS.has(item.key) && ["DENTED", "BROKEN", "MISSING", "NOT_WORKING"].includes(item.status));
  return { score, label, critical };
}

export function serializeInspection(items: Array<{ key: string; label: string; status: InspectionStatus; observation: string }>) {
  return items.map(({ status, ...item }) => ({ ...item, condition: status }));
}
