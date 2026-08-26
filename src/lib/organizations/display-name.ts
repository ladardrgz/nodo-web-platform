export function getOrganizationDisplayName(organization: { name: string; trade_name?: string | null }): string {
  return organization.trade_name?.trim() || organization.name.trim();
}
