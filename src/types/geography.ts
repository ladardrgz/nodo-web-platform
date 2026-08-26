export interface GeographyOption {
  id: string;
  name: string;
}

export interface OrganizationAddress {
  id: string;
  organization_id: string;
  country_id: string;
  province_id: string;
  locality_id: string;
  neighborhood_id: string | null;
  street: string;
  street_number: number | null;
  without_number: boolean;
  floor: string | null;
  apartment: string | null;
  postal_code: string | null;
  reference: string | null;
}

export interface InitialSetupLocationData {
  address: OrganizationAddress | null;
  countries: GeographyOption[];
  provinces: GeographyOption[];
  localities: GeographyOption[];
  neighborhoods: GeographyOption[];
  defaultCountryId: string;
}

export interface InitialSetupConfirmationData {
  address: OrganizationAddress | null;
  formattedAddress: string | null;
  phoneDisplay: string | null;
}
