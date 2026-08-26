export interface OwnerOrganization {
  id: string;
  name: string;
  trade_name: string | null;
  logo_path: string | null;
  phone: string | null;
  contact_email: string | null;
  address: string | null;
  locality: string | null;
  province: string | null;
  description: string | null;
  status: "ACTIVE" | "SUSPENDED";
  initial_setup_completed: boolean;
  initial_setup_step: number;
}
