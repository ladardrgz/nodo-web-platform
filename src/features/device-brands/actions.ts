"use server";

import { z } from "zod";
import { createCustomBrandAction, createCustomDeviceModelAction } from "@/features/repairs/reception/actions";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const pageInput = z.object({ deviceTypeId: z.string().uuid(), query: z.string().trim().max(80).default(""), page: z.number().int().positive().default(1), pageSize: z.union([z.literal(5), z.literal(10)]).default(5) });

export type DeviceBrandAdminRow = { id: string; name: string; isActive: boolean; modelCount: number; models: string[]; isPrivate: boolean };

export async function getDeviceBrandPageAction(input: unknown): Promise<{ ok: boolean; message: string; data?: { rows: DeviceBrandAdminRow[]; total: number } }> {
  const parsed = pageInput.safeParse(input);
  if (!parsed.success) return { ok: false, message: "El tipo de dispositivo no es válido." };
  const { organization } = await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const type = await supabase.from("device_types").select("id").eq("id", parsed.data.deviceTypeId).eq("is_active", true).maybeSingle();
  if (type.error || !type.data) return { ok: false, message: "El tipo de dispositivo no está disponible." };
  const from = (parsed.data.page - 1) * parsed.data.pageSize;
  const query = parsed.data.query.replace(/\s+/g, " ");
  let request = supabase.from("device_type_brands").select("device_brands!inner(id,name,is_active,fk_organizacion_id)", { count: "exact" }).eq("fk_tipo_dispositivo_id", parsed.data.deviceTypeId).order("name", { referencedTable: "device_brands", ascending: true }).range(from, from + parsed.data.pageSize - 1);
  if (query) request = request.ilike("device_brands.name", `%${query}%`);
  const { data, error, count } = await request;
  if (error) return { ok: false, message: "No se pudieron consultar las marcas." };
  const brands = (data ?? []).flatMap((row) => {
    const brand = row.device_brands as unknown as { id: string; name: string; is_active: boolean; fk_organizacion_id: string | null } | null;
    return brand ? [brand] : [];
  });
  const ids = brands.map((brand) => brand.id);
  const models = ids.length ? await supabase.from("device_models").select("fk_marca_dispositivo_id,name").eq("fk_tipo_dispositivo_id", parsed.data.deviceTypeId).in("fk_marca_dispositivo_id", ids).eq("is_active", true).order("name").limit(100) : { data: [], error: null };
  if (models.error) return { ok: false, message: "No se pudieron consultar los modelos asociados." };
  return { ok: true, message: "Marcas cargadas.", data: { total: count ?? 0, rows: brands.map((brand) => { const modelNames = (models.data ?? []).filter((model) => model.fk_marca_dispositivo_id === brand.id).map((model) => model.name); return { id: brand.id, name: brand.name, isActive: brand.is_active, modelCount: modelNames.length, models: modelNames, isPrivate: brand.fk_organizacion_id === organization.id }; }) } };
}

export async function createDeviceBrandFromAdminAction(input: { name: string; deviceTypeId: string }) { return createCustomBrandAction({ name: input.name, typeId: input.deviceTypeId }); }
export async function createDeviceModelFromAdminAction(input: { name: string; deviceTypeId: string; brandId: string }) { return createCustomDeviceModelAction({ name: input.name, typeId: input.deviceTypeId, brandId: input.brandId }); }

export async function deletePrivateDeviceBrandAction(input: { deviceTypeId: string; brandId: string }): Promise<{ ok: boolean; message: string }> {
  const parsed = z.object({ deviceTypeId: z.string().uuid(), brandId: z.string().uuid() }).safeParse(input);
  if (!parsed.success) return { ok: false, message: "La marca no es válida." };
  await requireOwnerOrganization();
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("delete_private_device_brand", { p_device_type_id: parsed.data.deviceTypeId, p_device_brand_id: parsed.data.brandId });
  if (!error) return { ok: true, message: "Marca eliminada del catálogo." };
  if (error.message.includes("DEVICE_BRAND_IN_USE")) return { ok: false, message: "Esta marca no puede eliminarse porque ya forma parte del historial de dispositivos o reparaciones." };
  return { ok: false, message: "No tenés permiso para eliminar esta marca." };
}
