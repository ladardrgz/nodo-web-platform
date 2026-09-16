import { ServiceOrderStatus } from "../value-objects/ServiceOrderStatus";

export interface ServiceOrderProps {
  id: string;
  organizationId: string;
  receptionId: string;
  orderNumber: number;
  status: ServiceOrderStatus;
  openedAt: string;
}

/** Domain entity: its status cannot be changed by assigning a field directly. */
export class ServiceOrder {
  constructor(private readonly props: ServiceOrderProps) {}

  get id() { return this.props.id; }
  get status() { return this.props.status; }
  get orderNumber() { return this.props.orderNumber; }

  transitionTo(next: ServiceOrderStatus) {
    if (this.props.status.isTerminal) throw new Error("TERMINAL_SERVICE_ORDER");
    return new ServiceOrder({ ...this.props, status: next });
  }
}
