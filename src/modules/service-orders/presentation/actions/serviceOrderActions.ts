"use server";
import { revalidatePath } from "next/cache";
import { CreateServiceOrderUseCase } from "@/modules/service-orders/application/use-cases/CreateServiceOrderUseCase";
import { ChangeServiceOrderStatusUseCase } from "@/modules/service-orders/application/use-cases/ChangeServiceOrderStatusUseCase";
import { SupabaseServiceOrderRepository } from "@/modules/service-orders/infrastructure/repositories/SupabaseServiceOrderRepository";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export async function createServiceOrderAction(receptionId: string) { await requireOwnerOrganization(); const id = await new CreateServiceOrderUseCase(new SupabaseServiceOrderRepository()).execute({ receptionId }); revalidatePath("/repairs"); return id; }
export async function changeServiceOrderStatusAction(orderId: string, statusCode: string, note?: string) { await requireOwnerOrganization(); await new ChangeServiceOrderStatusUseCase(new SupabaseServiceOrderRepository()).execute({ orderId, statusCode, note }); revalidatePath("/repairs"); revalidatePath(`/repairs/${orderId}`); }
