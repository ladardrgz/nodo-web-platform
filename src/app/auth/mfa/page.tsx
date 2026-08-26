import { forbidden } from "next/navigation";

import { MfaChallengeForm } from "@/features/auth/components/MfaChallengeForm";
import { sanitizeInternalRedirect } from "@/lib/auth/redirects";
import { requireAuth } from "@/lib/auth/session";

export default async function MfaChallengePage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const context = await requireAuth();
  if (context.profile.role !== "SUPERADMIN") forbidden();
  const requested = sanitizeInternalRedirect((await searchParams).next);
  const destination = requested?.startsWith("/superadmin") ? requested : "/superadmin";
  return <main className="grid min-h-screen place-items-center bg-app px-4 py-10"><MfaChallengeForm destination={destination} /></main>;
}
