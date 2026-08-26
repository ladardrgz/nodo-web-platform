import { ArrowRight, Plus } from "lucide-react";
import Link from "next/link";

import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { EmptyState } from "@/components/ui/EmptyState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { RepairOrder } from "@/features/repairs/types";
import { formatArgentinaDateTime } from "@/lib/argentina-time";

export function RecentRepairs({ repairs }: { repairs: RepairOrder[] }) {
  const recent = repairs.slice(0, 5);

  return (
    <Card className="overflow-hidden">
      <header className="flex items-start justify-between gap-4 border-b border-app-border px-5 py-4">
        <div><h2 className="font-bold text-app-text">Reparaciones recientes</h2><p className="mt-1 text-xs text-app-text-muted">Las cinco órdenes actualizadas más recientemente.</p></div>
        {recent.length ? <Link className="inline-flex min-h-9 shrink-0 items-center gap-1 rounded-lg px-2 text-sm font-semibold text-accent transition-colors hover:bg-accent-soft hover:text-accent-strong focus-visible:outline-accent" href="/repairs">Ver todas<ArrowRight aria-hidden="true" className="size-4" /></Link> : null}
      </header>
      {recent.length ? (
        <ol className="divide-y divide-app-border">
          {recent.map((repair) => (
            <li key={repair.id}>
              <Link className="grid gap-3 px-5 py-4 transition-colors hover:bg-app-surface-soft focus-visible:outline-accent sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center" href={`/repairs/${repair.id}`}>
                <div className="min-w-0">
                  <p className="text-xs font-bold uppercase tracking-wide text-accent">{repair.orderNumber}</p>
                  <strong className="mt-1 block truncate text-sm text-app-text">{repair.device.brand} {repair.device.model} · {repair.customerName}</strong>
                  <p className="mt-1 text-xs text-app-text-muted">Actualizada {formatArgentinaDateTime(repair.updatedAt)}</p>
                </div>
                <StatusBadge compact status={repair.status} />
              </Link>
            </li>
          ))}
        </ol>
      ) : (
        <EmptyState
          action={<ButtonLink href="/repairs/new"><Plus aria-hidden="true" className="size-4" />Crear primera reparación</ButtonLink>}
          description="Cuando registres una orden, vas a encontrar aquí sus datos y estado más reciente."
          title="Todavía no registraste reparaciones"
        />
      )}
    </Card>
  );
}
