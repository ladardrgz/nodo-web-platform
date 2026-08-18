export const APP_ROLES = {
  SUPERADMIN: "SUPERADMIN",
  OWNER: "OWNER",
  CUSTOMER: "CUSTOMER",
  TECHNICIAN: "TECHNICIAN",
} as const;

export type AppRole = (typeof APP_ROLES)[keyof typeof APP_ROLES];
export type ProfileStatus = "ACTIVE" | "SUSPENDED" | "DISABLED";

export interface AuthProfile {
  id: string;
  first_name: string | null;
  last_name: string | null;
  display_name: string | null;
  role: AppRole;
  organization_id: string | null;
  must_change_password: boolean;
  status: ProfileStatus;
}

export interface AuthContext {
  userId: string;
  email: string | null;
  profile: AuthProfile;
}
