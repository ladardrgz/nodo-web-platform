import "server-only";

import { SupabaseServiceOrderRepository } from "@/modules/service-orders/infrastructure/repositories/SupabaseServiceOrderRepository";
import type { RepairDetail, RepairOrder } from "@/features/repairs/types";
import type { ServiceOrderListItem } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";

function legacyView(order: ServiceOrderListItem): RepairOrder {
  return {
    id: order.id,
    orderNumber: `#${String(order.orderNumber).padStart(6, "0")}`,
    customerId: order.customerId,
    customerName: order.customerName,
    device: {
      id: order.device.id,
      type:
        order.device.type === "Notebook"
          ? "NOTEBOOK"
          : order.device.type === "Desktop PC"
            ? "DESKTOP"
            : "OTHER",
      brand: order.device.brand,
      model: order.device.model,
      color: order.device.color,
      serialNumber: order.device.serialNumber,
    },
    deviceTypeName: order.device.type,
    status: order.status.code,
    intakeStatus: "CONFIRMED",
    receivedAt: order.receivedAt,
    updatedAt: order.updatedAt,
    reportedProblem: order.reportedProblem,
    intakeNotes: "",
    accessories: [],
    timeline: [],
  };
}

/** @deprecated Compatibility facade. New code imports the service-orders module. */
export async function listOrganizationRepairs(
  _organizationId?: string,
  _limit?: number,
) {
  void _organizationId;
  void _limit;
  return (await new SupabaseServiceOrderRepository().list()).map(legacyView);
}

export async function getOrganizationRepair(
  _organizationId: string,
  orderId: string,
): Promise<RepairDetail | null> {
  const order = await new SupabaseServiceOrderRepository().getById(orderId);
  if (!order) return null;
  return {
    ...legacyView(order),
    calculatedCondition: "No disponible",
    conditionScore: 0,
    inspection: [],
    photos: [],
  };
}
