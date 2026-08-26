import "server-only";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { GeographyOption, InitialSetupLocationData, OrganizationAddress } from "@/types/geography";

const sortOptions = (options: GeographyOption[]) => options.sort((a, b) => a.name.localeCompare(b.name, "es"));

export async function getInitialSetupLocationData(organizationId: string): Promise<InitialSetupLocationData> {
  const supabase = await createSupabaseServerClient();
  const [{ data: countryRows }, { data: addressRow }] = await Promise.all([
    supabase.from("countries").select("id,name").eq("is_active", true).order("name"),
    supabase.from("organization_addresses").select("id,organization_id,country_id,province_id,locality_id,neighborhood_id,street,street_number,without_number,floor,apartment,postal_code,reference").eq("organization_id", organizationId).maybeSingle(),
  ]);

  const countries = sortOptions((countryRows ?? []) as GeographyOption[]);
  const address = (addressRow ?? null) as OrganizationAddress | null;
  const defaultCountryId = address?.country_id ?? countries.find((country) => country.id === "AR")?.id ?? countries[0]?.id ?? "";

  const { data: provinceRows } = defaultCountryId
    ? await supabase.from("provinces").select("id,name").eq("country_id", defaultCountryId).eq("is_active", true).order("name")
    : { data: [] };
  const { data: localityRows } = address?.province_id
    ? await supabase.from("localities").select("id,name").eq("province_id", address.province_id).eq("is_active", true).order("name")
    : { data: [] };
  const { data: neighborhoodRows } = address?.locality_id
    ? await supabase.from("neighborhoods").select("id,name").eq("locality_id", address.locality_id).eq("is_active", true).order("name")
    : { data: [] };

  return {
    address,
    countries,
    defaultCountryId,
    provinces: sortOptions((provinceRows ?? []) as GeographyOption[]),
    localities: sortOptions((localityRows ?? []) as GeographyOption[]),
    neighborhoods: sortOptions((neighborhoodRows ?? []) as GeographyOption[]),
  };
}
