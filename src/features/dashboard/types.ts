import type { RepairOrder } from "@/features/repairs/types";
import type { AgendaEvent } from "@/features/dashboard/agenda/types";
import type { WeatherLocation } from "@/features/dashboard/weather/types";

export interface OwnerActivityEvent {
  createdAt: string;
  entityType: string;
  eventType: string;
  id: string;
}

export interface OwnerActivityPage {
  error: boolean;
  events: OwnerActivityEvent[];
  page: number;
  pageSize: number;
  totalItems: number;
  totalPages: number;
}

export interface OwnerDashboardData {
  activity: OwnerActivityPage;
  agendaEvents: AgendaEvent[];
  locationLabel: string | null;
  logoUrl: string | null;
  repairs: RepairOrder[];
  weatherLocation: WeatherLocation | null;
}
