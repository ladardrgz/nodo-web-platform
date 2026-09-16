import type { Metadata } from "next";
import { DeviceBrandsManager } from "@/features/device-brands/components/DeviceBrandsManager";
import { requireOwnerOrganization } from "@/lib/organizations/setup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Marcas de dispositivos" };

export default async function DeviceBrandsPage({ searchParams }: { searchParams: Promise<{ deviceType?: string }> }) {
  await requireOwnerOrganization();
  const [{ deviceType }, supabase] = await Promise.all([searchParams, createSupabaseServerClient()]);
  const { data } = await supabase.from("device_types").select("id,name").eq("is_active", true).order("name");
  return <DeviceBrandsManager deviceTypes={data ?? []} initialDeviceTypeId={deviceType} />;
}
