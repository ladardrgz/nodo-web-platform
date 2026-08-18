import { Bot, UserRound, Wrench } from "lucide-react";

import type { RepairTimelineEvent } from "@/features/repairs/types";
import { formatDateTime } from "@/lib/format";

const actorConfig = {
  SYSTEM: { label: "Sistema", icon: Bot, className: "bg-slate-100 text-slate-700" },
  ADMIN: { label: "Administración", icon: Wrench, className: "bg-blue-50 text-blue-700" },
  CUSTOMER: { label: "Cliente", icon: UserRound, className: "bg-violet-50 text-violet-700" },
};

export function RepairTimeline({ events }: { events: RepairTimelineEvent[] }) {
  return (
    <ol className="space-y-0">
      {events.map((event, index) => {
        const actor = actorConfig[event.actor];
        const Icon = actor.icon;
        return (
          <li className="relative grid grid-cols-[40px_1fr] gap-3 pb-6 last:pb-0" key={event.id}>
            {index < events.length - 1 ? <span className="absolute bottom-0 left-5 top-10 w-px bg-border" /> : null}
            <span className={`relative z-10 grid size-10 place-items-center rounded-full ${actor.className}`}><Icon className="size-4" /></span>
            <div className="pt-1">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <strong className="text-sm text-primary">{event.title}</strong>
                <time className="text-xs font-medium text-muted">{formatDateTime(event.createdAt)}</time>
              </div>
              {event.description ? <p className="mt-1 text-sm leading-6 text-muted">{event.description}</p> : null}
              <p className="mt-1 text-xs font-semibold text-slate-400">{actor.label}</p>
            </div>
          </li>
        );
      })}
    </ol>
  );
}
