import { describe, expect, it } from "vitest";
import { ServiceOrder } from "../src/modules/service-orders/domain/entities/ServiceOrder";
import { ServiceOrderStatus } from "../src/modules/service-orders/domain/value-objects/ServiceOrderStatus";

describe("ServiceOrder", () => {
  it("does not transition from a terminal state", () => {
    const delivered = new ServiceOrderStatus("1", "DELIVERED", "Entregada", true);
    const order = new ServiceOrder({ id: "o", organizationId: "org", receptionId: "r", orderNumber: 1, status: delivered, openedAt: new Date().toISOString() });
    expect(() => order.transitionTo(new ServiceOrderStatus("2", "IN_PROGRESS", "En curso", false))).toThrow("TERMINAL_SERVICE_ORDER");
  });
});
