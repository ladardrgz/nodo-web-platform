import type { ServiceOrderRepository } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";
export class RecordWorkTimeUseCase { constructor(private readonly repository: ServiceOrderRepository) {} execute(input: { orderId: string; taskId?: string; startedAt: string; endedAt?: string; notes?: string }) { return this.repository.recordTime(input); } }
