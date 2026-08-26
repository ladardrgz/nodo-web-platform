import type { SVGProps } from "react";

import type { QuickLinkService } from "@/features/quick-links/config";

export function BrandIcon({ service, ...props }: SVGProps<SVGSVGElement> & { service: QuickLinkService }) {
  const common = { viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true, ...props };
  if (service === "GOOGLE") return <svg {...common}><path d="M20 12.2a8 8 0 1 1-2.2-5.55" /><path d="M20 12h-8" /><path d="M20 12c0 4.7-3.2 8-8 8" /></svg>;
  if (service === "GMAIL") return <svg {...common}><rect height="15" rx="2" width="20" x="2" y="4.5" /><path d="m3 6 9 7 9-7" /><path d="M7 19V9.1M17 19V9.1" /></svg>;
  if (service === "YOUTUBE") return <svg {...common}><path d="M21.3 7.1a2.5 2.5 0 0 0-1.8-1.8C17.9 4.9 15.4 4.8 12 4.8s-5.9.1-7.5.5a2.5 2.5 0 0 0-1.8 1.8A19 19 0 0 0 2.3 12a19 19 0 0 0 .4 4.9 2.5 2.5 0 0 0 1.8 1.8c1.6.4 4.1.5 7.5.5s5.9-.1 7.5-.5a2.5 2.5 0 0 0 1.8-1.8 19 19 0 0 0 .4-4.9 19 19 0 0 0-.4-4.9Z" /><path d="m10 9 5 3-5 3Z" fill="currentColor" stroke="none" /></svg>;
  if (service === "FACEBOOK") return <svg {...common}><path d="M14 21v-8h3l.5-3H14V8.3c0-.9.3-1.8 1.9-1.8H18V3.8c-.5-.1-1.5-.2-2.7-.2-2.7 0-4.6 1.7-4.6 4.7V10H8v3h2.7v8" /></svg>;
  if (service === "WHATSAPP") return <svg {...common}><path d="M20.5 11.7a8.5 8.5 0 0 1-12.6 7.4L3 20.5l1.4-4.7a8.5 8.5 0 1 1 16.1-4.1Z" /><path d="M8.2 7.8c.4 3.4 2.7 5.8 6.1 6.7l1.5-1.5-2.3-1.1-.8 1c-1.5-.6-2.7-1.8-3.3-3.3l1-.8-1.1-2.3-1.1 1.3Z" /></svg>;
  if (service === "INSTAGRAM") return <svg {...common}><rect height="18" rx="5" width="18" x="3" y="3" /><circle cx="12" cy="12" r="4" /><circle cx="17.5" cy="6.5" fill="currentColor" r="1" stroke="none" /></svg>;
  return <svg {...common}><path d="m21 4-3 16-5.5-4-3 3 .5-5.5L4 11l17-7Z" /><path d="m10 13.5 8-6" /></svg>;
}
