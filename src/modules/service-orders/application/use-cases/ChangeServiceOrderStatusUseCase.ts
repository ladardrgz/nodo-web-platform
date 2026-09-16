import type { ServiceOrderRepository } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";
export class ChangeServiceOrderStatusUseCase { constructor(private readonly repository: ServiceOrderRepository) {} execute(input: { orderId: string; statusCode: string; note?: string }) { return this.repository.changeStatus(input); } }
