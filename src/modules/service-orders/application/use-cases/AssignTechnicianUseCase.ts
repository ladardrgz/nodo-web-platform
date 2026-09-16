import type { ServiceOrderRepository } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";
export class AssignTechnicianUseCase { constructor(private readonly repository: ServiceOrderRepository) {} execute(input: { orderId: string; technicianUserId: string; assignmentRole?: string; primary?: boolean }) { return this.repository.assignTechnician(input); } }
