import { ArrowRight, CalendarDays, UserRound } from "lucide-react";
import Link from "next/link";

import { Card } from "@/components/ui/Card";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { ServiceOrderListItem } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";
import { formatDate } from "@/lib/format";

export function RepairCard({ repair }: { repair: ServiceOrderListItem }) {
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-wide text-accent">
            #{String(repair.orderNumber).padStart(6, "0")}
          </p>
          <h2 className="mt-1 font-bold text-primary">
            {repair.device.brand} {repair.device.model}
          </h2>
        </div>
        <StatusBadge compact label={repair.status.name} status={repair.status.code} />
      </div>
      <p className="mt-3 line-clamp-2 text-sm leading-6 text-muted">
        {repair.reportedProblem}
      </p>
      <div className="mt-4 grid gap-2 text-xs text-muted">
        <span className="flex items-center gap-2">
          <UserRound className="size-4" />
          {repair.customerName}
        </span>
        <span className="flex items-center gap-2">
          <CalendarDays className="size-4" />
          Ingresó el {formatDate(repair.receivedAt)}
        </span>
      </div>
      <Link
        className="mt-4 flex min-h-10 items-center justify-center gap-2 rounded-lg bg-surface-soft text-sm font-bold text-primary transition-colors hover:bg-surface-hover hover:text-accent focus-visible:outline-2 focus-visible:outline-accent"
        href={`/repairs/${repair.id}`}
      >
        Ver detalle <ArrowRight className="size-4" />
      </Link>
    </Card>
  );
}
