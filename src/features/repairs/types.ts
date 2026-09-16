import type { Device } from "@/features/customers/types";

/**
 * Estados conocidos que puede atravesar una reparación.
 *
 * `as const` hace que TypeScript conserve cada valor como un literal
 * específico, por ejemplo "RECEIVED", en lugar de convertirlo en `string`.
 *
 * Nota: actualmente `RepairStatus` está definido como `string`, por lo que
 * esta constante todavía no restringe el tipo de estado de una reparación.
 */
export const REPAIR_STATUS = {
  RECEIVED: "RECEIVED",
  DIAGNOSING: "DIAGNOSING",
  WAITING_APPROVAL: "WAITING_APPROVAL",
  WAITING_PART: "WAITING_PART",
  IN_REPAIR: "IN_REPAIR",
  DELAYED: "DELAYED",
  READY_FOR_PICKUP: "READY_FOR_PICKUP",
  DELIVERED: "DELIVERED",
  CANCELLED: "CANCELLED",
  UNREPAIRABLE: "UNREPAIRABLE",
} as const;

/**
 * Representa el estado actual de una reparación.
 *
 * Actualmente acepta cualquier cadena.
 * Esto permite trabajar con estados provenientes de fuentes externas
 * o de base de datos que no necesariamente estén incluidos todavía
 * en `REPAIR_STATUS`.
 */
export type RepairStatus = string;

/**
 * Representa el estado del proceso de recepción del dispositivo.
 *
 * - DRAFT: la recepción todavía está siendo preparada.
 * - CONFIRMED: la recepción fue confirmada.
 */
export type IntakeStatus = "DRAFT" | "CONFIRMED";

/**
 * Identifica quién originó un evento dentro del historial de la reparación.
 *
 * - SYSTEM: evento generado automáticamente por el sistema.
 * - ADMIN: evento generado por un usuario administrativo.
 * - CUSTOMER: evento asociado al cliente.
 */
export type TimelineActor = "SYSTEM" | "ADMIN" | "CUSTOMER";

/**
 * Representa un evento individual dentro de la línea de tiempo
 * de una reparación.
 *
 * Permite registrar qué ocurrió, cuándo ocurrió y quién originó
 * el acontecimiento.
 */
export interface RepairTimelineEvent {
  id: string;
  title: string;
  description?: string;
  createdAt: string;
  actor: TimelineActor;
}

/**
 * Representa la información principal de una orden de reparación.
 *
 * Reúne los datos necesarios para identificar la orden, el cliente,
 * el dispositivo recibido, su estado actual y la información básica
 * registrada durante la recepción.
 */
export interface RepairOrder {
  id: string;
  orderNumber: string;
  customerId: string;
  customerName: string;
  device: Device;
  deviceTypeName?: string;
  status: RepairStatus;
  intakeStatus: IntakeStatus;
  receivedAt: string;
  updatedAt: string;
  estimatedDate?: string;
  reportedProblem: string;
  intakeNotes: string;
  accessories: string[];
  timeline: RepairTimelineEvent[];
}

/**
 * Representa un elemento individual inspeccionado durante
 * la recepción o revisión física del dispositivo.
 *
 * Registra la condición encontrada, su severidad, observaciones
 * adicionales y si el elemento es considerado crítico.
 */
export interface RepairInspectionItem {
  id: string;
  key: string;
  label: string;
  condition: string;
  severity: number | null;
  observation: string;
  critical: boolean;
}

/**
 * Representa una fotografía asociada a una reparación.
 *
 * La fotografía puede incluir una descripción y puede estar vinculada
 * específicamente a un elemento de la inspección mediante
 * `inspectionItemKey`.
 */
export interface RepairPhoto {
  id: string;
  url: string;
  description: string | null;
  inspectionItemKey: string | null;
  createdAt: string;
}

/**
 * Representa la vista detallada de una reparación.
 *
 * Extiende `RepairOrder`, por lo que conserva toda la información
 * básica de la orden y agrega el resultado de la evaluación física,
 * los elementos inspeccionados y las fotografías registradas.
 */
export interface RepairDetail extends RepairOrder {
  calculatedCondition: string;
  conditionScore: number;
  inspection: RepairInspectionItem[];
  photos: RepairPhoto[];
}
