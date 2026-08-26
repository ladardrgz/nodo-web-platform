import type { Metadata } from "next";
import { Suspense } from "react";

import { OperationalSummary } from "@/features/dashboard/components/OperationalSummary";
import { OwnerActivityList } from "@/features/dashboard/components/OwnerActivityList";
import { OwnerDashboardHero } from "@/features/dashboard/components/OwnerDashboardHero";
import { RecentRepairs } from "@/features/dashboard/components/RecentRepairs";
import { TodayPanel } from "@/features/dashboard/components/TodayPanel";
import { getOwnerDashboardData } from "@/features/dashboard/data";
import { argentinaDateKey } from "@/features/dashboard/agenda/date-utils";
import { OwnerSetupWelcome } from "@/features/organizations/components/OwnerSetupWelcome";
import { OwnerWeather } from "@/features/dashboard/weather/components/OwnerWeather";
import { WeatherCardSkeleton } from "@/features/dashboard/weather/components/WeatherCardSkeleton";
import { argentinaGreeting, formatArgentinaLongDate } from "@/lib/argentina-time";
import { getOrganizationDisplayName } from "@/lib/organizations/display-name";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

export const metadata: Metadata = { title: "Dashboard" };

interface DashboardSearchParams {
  activityPage?: string | string[];
}

function parseActivityPage(value: string | string[] | undefined): number {
  const parsed = Number(Array.isArray(value) ? value[0] : value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 1;
}

export default async function DashboardPage({ searchParams }: { searchParams: Promise<DashboardSearchParams> }) {
  const { context, organization } = await requireOwnerOrganization({ allowIncompleteSetup: true });
  const firstName = context.profile.first_name?.trim()
    || context.profile.display_name?.trim().split(/\s+/)[0]
    || context.email?.split("@")[0]
    || "Propietario";

  if (!organization.initial_setup_completed) {
    return <OwnerSetupWelcome firstName={firstName} initialGreeting={argentinaGreeting()} />;
  }

  const params = await searchParams;
  const todayKey = argentinaDateKey();
  const dashboard = await getOwnerDashboardData(organization, parseActivityPage(params.activityPage), todayKey);
  const organizationName = getOrganizationDisplayName(organization);
  const dateLabel = formatArgentinaLongDate();

  return (
    <div className="space-y-6 lg:space-y-8">
      <OwnerDashboardHero
        firstName={firstName}
        greeting={argentinaGreeting()}
        logoUrl={dashboard.logoUrl}
        organizationName={organizationName}
        showPrimaryAction={dashboard.repairs.length > 0}
      />

      <OperationalSummary repairs={dashboard.repairs} />

      <TodayPanel
        dateLabel={dateLabel}
        events={dashboard.agendaEvents}
        locationLabel={dashboard.locationLabel}
        todayKey={todayKey}
        weather={<Suspense fallback={<WeatherCardSkeleton />}><OwnerWeather location={dashboard.weatherLocation} /></Suspense>}
      />

      <div className="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1.2fr)_minmax(340px,0.8fr)]">
        <RecentRepairs repairs={dashboard.repairs} />
        <OwnerActivityList activity={dashboard.activity} />
      </div>
    </div>
  );
}
