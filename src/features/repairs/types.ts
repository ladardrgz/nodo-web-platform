import type { Device } from "@/features/customers/types";

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

export type RepairStatus =
  (typeof REPAIR_STATUS)[keyof typeof REPAIR_STATUS];

export type IntakeStatus = "DRAFT" | "CONFIRMED";
export type TimelineActor = "SYSTEM" | "ADMIN" | "CUSTOMER";

export interface RepairTimelineEvent {
  id: string;
  title: string;
  description?: string;
  createdAt: string;
  actor: TimelineActor;
}

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

export interface RepairInspectionItem {
  id: string;
  key: string;
  label: string;
  condition: string;
  severity: number | null;
  observation: string;
  critical: boolean;
}

export interface RepairPhoto {
  id: string;
  url: string;
  description: string | null;
  inspectionItemKey: string | null;
  createdAt: string;
}

export interface RepairDetail extends RepairOrder {
  calculatedCondition: string;
  conditionScore: number;
  inspection: RepairInspectionItem[];
  photos: RepairPhoto[];
}
