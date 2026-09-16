export class ServiceOrderStatus {
  constructor(readonly id: string, readonly code: string, readonly name: string, readonly isTerminal: boolean) {
    if (!code.trim()) throw new Error("INVALID_SERVICE_ORDER_STATUS");
  }
}
