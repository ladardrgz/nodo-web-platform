import {
  REPAIR_STATUS,
  type RepairStatus,
} from "@/features/repairs/types";

interface RepairStatusDefinition {
  label: string;
  shortLabel: string;
  description: string;
  badgeClassName: string;
  dotClassName: string;
}

export const repairStatusConfig: Record<
  RepairStatus,
  RepairStatusDefinition
> = {
  [REPAIR_STATUS.RECEIVED]: {
    label: "Recibido",
    shortLabel: "Recibido",
    description: "El equipo ingresó al servicio técnico.",
    badgeClassName: "bg-blue-50 text-blue-800 ring-blue-200",
    dotClassName: "bg-blue-600",
  },
  [REPAIR_STATUS.DIAGNOSING]: {
    label: "En diagnóstico",
    shortLabel: "Diagnóstico",
    description: "El equipo está siendo revisado.",
    badgeClassName: "bg-cyan-50 text-cyan-800 ring-cyan-200",
    dotClassName: "bg-cyan-600",
  },
  [REPAIR_STATUS.WAITING_APPROVAL]: {
    label: "Esperando aprobación",
    shortLabel: "Aprobación",
    description: "El cliente debe decidir sobre el presupuesto.",
    badgeClassName: "bg-violet-50 text-violet-800 ring-violet-200",
    dotClassName: "bg-violet-600",
  },
  [REPAIR_STATUS.WAITING_PART]: {
    label: "Esperando repuesto",
    shortLabel: "Repuesto",
    description: "La reparación está pendiente de una pieza.",
    badgeClassName: "bg-amber-50 text-amber-800 ring-amber-200",
    dotClassName: "bg-amber-600",
  },
  [REPAIR_STATUS.IN_REPAIR]: {
    label: "En reparación",
    shortLabel: "Reparación",
    description: "El trabajo técnico está en curso.",
    badgeClassName: "bg-indigo-50 text-indigo-800 ring-indigo-200",
    dotClassName: "bg-indigo-600",
  },
  [REPAIR_STATUS.DELAYED]: {
    label: "Demorado",
    shortLabel: "Demorado",
    description: "La orden registra una demora informada.",
    badgeClassName: "bg-orange-50 text-orange-800 ring-orange-200",
    dotClassName: "bg-orange-600",
  },
  [REPAIR_STATUS.READY_FOR_PICKUP]: {
    label: "Listo para retirar",
    shortLabel: "Listo",
    description: "El equipo está disponible para su entrega.",
    badgeClassName: "bg-emerald-50 text-emerald-800 ring-emerald-200",
    dotClassName: "bg-emerald-600",
  },
  [REPAIR_STATUS.DELIVERED]: {
    label: "Entregado",
    shortLabel: "Entregado",
    description: "El equipo fue entregado al cliente.",
    badgeClassName: "bg-slate-100 text-slate-700 ring-slate-200",
    dotClassName: "bg-slate-500",
  },
  [REPAIR_STATUS.CANCELLED]: {
    label: "Cancelado",
    shortLabel: "Cancelado",
    description: "La orden fue cancelada.",
    badgeClassName: "bg-rose-50 text-rose-800 ring-rose-200",
    dotClassName: "bg-rose-600",
  },
  [REPAIR_STATUS.UNREPAIRABLE]: {
    label: "No reparable",
    shortLabel: "No reparable",
    description: "El equipo no puede repararse.",
    badgeClassName: "bg-red-50 text-red-800 ring-red-200",
    dotClassName: "bg-red-600",
  },
};

export const repairStatusOptions = Object.entries(repairStatusConfig).map(
  ([value, definition]) => ({
    value: value as RepairStatus,
    label: definition.label,
  }),
);
