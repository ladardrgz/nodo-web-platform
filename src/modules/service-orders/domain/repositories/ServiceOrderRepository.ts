export interface ServiceOrderListItem {
  id: string; orderNumber: number; receptionId: string; status: { code: string; name: string; isTerminal: boolean };
  customerId: string; customerName: string; device: { id: string; type: string; brand: string; model: string; color?: string; serialNumber?: string };
  reportedProblem: string; receivedAt: string; updatedAt: string;
}

export interface ServiceOrderRepository {
  createFromReception(input: { receptionId: string; priorityId?: string; complexityId?: string; notes?: string }): Promise<string>;
  list(): Promise<ServiceOrderListItem[]>;
  getById(id: string): Promise<ServiceOrderListItem | null>;
  listStatuses(): Promise<Array<{ id: string; code: string; name: string; isTerminal: boolean }>>;
  changeStatus(input: { orderId: string; statusCode: string; note?: string }): Promise<void>;
  assignTechnician(input: { orderId: string; technicianUserId: string; assignmentRole?: string; primary?: boolean }): Promise<string>;
  unassignTechnician(assignmentId: string): Promise<void>;
  recordTime(input: { orderId: string; taskId?: string; startedAt: string; endedAt?: string; notes?: string }): Promise<string>;
}
