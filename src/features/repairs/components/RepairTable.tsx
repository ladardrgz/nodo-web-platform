import { ArrowRight } from "lucide-react";
import Link from "next/link";

import { StatusBadge } from "@/components/ui/StatusBadge";
import type { ServiceOrderListItem } from "@/modules/service-orders/domain/repositories/ServiceOrderRepository";
import { formatDate } from "@/lib/format";

export function RepairTable({ repairs }: { repairs: ServiceOrderListItem[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[760px] border-collapse text-left">
        <thead>
          <tr className="border-b border-border bg-surface-soft text-xs font-bold uppercase tracking-wide text-muted">
            <th className="px-5 py-3">Orden</th>
            <th className="px-5 py-3">Cliente</th>
            <th className="px-5 py-3">Equipo</th>
            <th className="px-5 py-3">Ingreso</th>
            <th className="px-5 py-3">Estado</th>
            <th className="px-5 py-3 text-right">Acción</th>
          </tr>
        </thead>
        <tbody>
          {repairs.map((repair) => (
            <tr className="border-b border-border/80 last:border-0 transition-colors hover:bg-surface-hover" key={repair.id}>
              <td className="px-5 py-4">
                <Link className="font-bold text-primary hover:text-accent" href={`/repairs/${repair.id}`}>
                  #{String(repair.orderNumber).padStart(6, "0")}
                </Link>
              </td>
              <td className="px-5 py-4 text-sm font-semibold text-primary">{repair.customerName}</td>
              <td className="px-5 py-4">
                <strong className="block text-sm text-primary">{repair.device.brand} {repair.device.model}</strong>
                <span className="text-xs text-muted">{repair.reportedProblem}</span>
              </td>
              <td className="px-5 py-4 text-sm text-muted">{formatDate(repair.receivedAt)}</td>
              <td className="px-5 py-4"><StatusBadge compact label={repair.status.name} status={repair.status.code} /></td>
              <td className="px-5 py-4 text-right">
                <Link aria-label={`Abrir ${repair.orderNumber}`} className="inline-grid size-9 place-items-center rounded-lg text-muted hover:bg-surface-hover hover:text-accent focus-visible:outline-2 focus-visible:outline-accent" href={`/repairs/${repair.id}`}>
                  <ArrowRight className="size-4" />
                </Link>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
