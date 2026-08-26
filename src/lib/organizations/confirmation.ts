import "server-only";

import { formatAddress } from "@/lib/organizations/address";
import type { InitialSetupConfirmationData, InitialSetupLocationData } from "@/types/geography";
import type { OwnerOrganization } from "@/types/organization";

export function buildInitialSetupConfirmationData(
  organization: OwnerOrganization,
  locationData: InitialSetupLocationData,
): InitialSetupConfirmationData {
  const address = locationData.address;
  if (!address) {
    return {
      address: null,
      formattedAddress: null,
      phoneDisplay: organization.phone,
    };
  }

  const country = locationData.countries.find((option) => option.id === address.country_id)?.name;
  const province = locationData.provinces.find((option) => option.id === address.province_id)?.name;
  const locality = locationData.localities.find((option) => option.id === address.locality_id)?.name;
  const neighborhood = locationData.neighborhoods.find((option) => option.id === address.neighborhood_id)?.name;

  return {
    address,
    formattedAddress: formatAddress({ ...address, country, province, locality, neighborhood }),
    phoneDisplay: organization.phone,
  };
}
