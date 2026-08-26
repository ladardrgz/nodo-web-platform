export interface GeographySelection {
  countryId: string;
  provinceId: string;
  localityId: string;
  neighborhoodId: string;
}

export function selectCountry<T extends GeographySelection>(values: T, countryId: string): T {
  return { ...values, countryId, provinceId: "", localityId: "", neighborhoodId: "" };
}

export function selectProvince<T extends GeographySelection>(values: T, provinceId: string): T {
  return { ...values, provinceId, localityId: "", neighborhoodId: "" };
}

export function selectLocality<T extends GeographySelection>(values: T, localityId: string): T {
  return { ...values, localityId, neighborhoodId: "" };
}
