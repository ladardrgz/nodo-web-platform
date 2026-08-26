import type { OrganizationAddress } from "@/types/geography";

interface AddressNames {
  country?: string | null;
  locality?: string | null;
  neighborhood?: string | null;
  province?: string | null;
}

export function formatAddress(address: Pick<OrganizationAddress,
  "apartment" | "floor" | "postal_code" | "reference" | "street" | "street_number" | "without_number"
> & AddressNames): string {
  const number = address.without_number ? "S/N" : String(address.street_number ?? "");
  const unit = [address.floor ? `Piso ${address.floor}` : null, address.apartment ? `Depto. ${address.apartment}` : null]
    .filter(Boolean)
    .join(", ");
  return [
    `${address.street} ${number}`.trim(),
    unit || null,
    address.neighborhood ? `Barrio ${address.neighborhood}` : null,
    address.locality,
    address.province,
    address.postal_code,
    address.country,
    address.reference ? `Referencia: ${address.reference}` : null,
  ].filter(Boolean).join(", ");
}
