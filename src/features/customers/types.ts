export type DeviceType =
  | "PHONE"
  | "NOTEBOOK"
  | "DESKTOP"
  | "TABLET"
  | "OTHER";

export interface Device {
  id: string;
  type: DeviceType;
  brand: string;
  model: string;
  color?: string;
  serialNumber?: string;
  imei?: string;
}

export interface CustomerHistoryItem {
  id: string;
  title: string;
  description: string;
  createdAt: string;
}

export interface Customer {
  id: string;
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
  address?: string;
  preferredContact: "PHONE" | "EMAIL" | "WHATSAPP";
  createdAt: string;
  devices: Device[];
  history: CustomerHistoryItem[];
}

export function getCustomerFullName(customer: Customer): string {
  return `${customer.firstName} ${customer.lastName}`;
}

export const deviceTypeLabels: Record<DeviceType, string> = {
  PHONE: "Celular",
  NOTEBOOK: "Notebook",
  DESKTOP: "Computadora",
  TABLET: "Tablet",
  OTHER: "Otro",
};
