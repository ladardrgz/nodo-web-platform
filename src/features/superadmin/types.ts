export type OrganizationStatus = "ACTIVE" | "SUSPENDED";
export type ProfileStatus = "ACTIVE" | "SUSPENDED" | "DISABLED";
export type AppRole = "SUPERADMIN" | "OWNER" | "CUSTOMER" | "TECHNICIAN";

export interface OrganizationListItem {
  id: string;
  name: string;
  slug: string;
  status: OrganizationStatus;
  isDevelopmentMock?: boolean;
}

export interface UserListItem {
  id: string;
  firstName: string;
  lastName: string;
  displayName: string;
  email: string;
  role: AppRole;
  status: ProfileStatus;
  organizationId: string;
  organizationName: string;
  invitationPending: boolean;
  isDevelopmentMock?: boolean;
}

export type OrganizationOption = Pick<OrganizationListItem, "id" | "name" | "slug">;
