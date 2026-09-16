import type { ServiceOrderRepository } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";
export class CreateServiceOrderUseCase { constructor(private readonly repository: ServiceOrderRepository) {} execute(input: { receptionId: string; priorityId?: string; complexityId?: string; notes?: string }) { return this.repository.createFromReception(input); } }
