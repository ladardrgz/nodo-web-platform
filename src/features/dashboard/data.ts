import "server-only";

import { agendaWindowRange } from "@/features/dashboard/agenda/date-utils";
import { listAgendaEventsForRange } from "@/features/dashboard/agenda/repository";
import type { OwnerDashboardData } from "@/features/dashboard/types";
import { listOrganizationRepairs } from "@/features/repairs/repository";
import { getInitialSetupLocationData } from "@/lib/organizations/geography";
import { getOrganizationLogoSignedUrl } from "@/lib/organizations/logo";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { OwnerOrganization } from "@/types/organization";

export const OWNER_ACTIVITY_PAGE_SIZE = 5;

function positivePage(value: number): number {
  return Number.isSafeInteger(value) && value > 0 ? value : 1;
}

export async function getOwnerDashboardData(
  organization: OwnerOrganization,
  requestedActivityPage: number,
  todayKey: string,
): Promise<OwnerDashboardData> {
  const supabase = await createSupabaseServerClient();
  const agendaRange = agendaWindowRange(todayKey);
  const requestedPage = positivePage(requestedActivityPage);
  const requestedFrom = (requestedPage - 1) * OWNER_ACTIVITY_PAGE_SIZE;
  const requestedTo = requestedFrom + OWNER_ACTIVITY_PAGE_SIZE - 1;
  const [locationData, logoUrl, activityQuery, agendaEvents, repairs] = await Promise.all([
    getInitialSetupLocationData(organization.id),
    getOrganizationLogoSignedUrl(organization.logo_path),
    supabase
      .from("audit_events")
      .select("id,event_type,entity_type,created_at", { count: "exact" })
      .eq("organization_id", organization.id)
      .order("created_at", { ascending: false })
      .range(requestedFrom, requestedTo),
    listAgendaEventsForRange({ ...agendaRange, organizationId: organization.id, todayKey }),
    listOrganizationRepairs(organization.id, 100).catch(() => []),
  ]);

  const totalItems = activityQuery.count ?? 0;
  const totalPages = Math.max(1, Math.ceil(totalItems / OWNER_ACTIVITY_PAGE_SIZE));
  const page = Math.min(requestedPage, totalPages);
  const from = (page - 1) * OWNER_ACTIVITY_PAGE_SIZE;
  const to = from + OWNER_ACTIVITY_PAGE_SIZE - 1;
  const activityResult = activityQuery.error || page === requestedPage
    ? activityQuery
    : await supabase
        .from("audit_events")
        .select("id,event_type,entity_type,created_at")
        .eq("organization_id", organization.id)
        .order("created_at", { ascending: false })
        .range(from, to);

  const address = locationData.address;
  const locality = address
    ? locationData.localities.find((option) => option.id === address.locality_id)?.name
    : null;
  const province = address
    ? locationData.provinces.find((option) => option.id === address.province_id)?.name
    : null;
  const country = address
    ? locationData.countries.find((option) => option.id === address.country_id)?.name
    : null;
  const locationLabel = [locality, province].filter(Boolean).join(", ") || null;
  const weatherLocation = address && locality && province && country
    ? { countryCode: address.country_id, countryName: country, locality, province }
    : null;
  return {
    activity: {
      error: Boolean(activityResult.error),
      events: (activityResult.data ?? []).map((event) => ({
        createdAt: event.created_at,
        entityType: event.entity_type,
        eventType: event.event_type,
        id: event.id,
      })),
      page,
      pageSize: OWNER_ACTIVITY_PAGE_SIZE,
      totalItems,
      totalPages,
    },
    agendaEvents,
    locationLabel,
    logoUrl,
    repairs,
    weatherLocation,
  };
}
