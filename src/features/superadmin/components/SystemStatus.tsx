import { CircleCheck, CircleDashed, CircleX, ServerCog } from "lucide-react";

import { ContextHelp } from "@/features/superadmin/components/ContextHelp";

type Verification = "VERIFIED" | "ERROR" | "NOT_CONFIGURED" | "NOT_VERIFIED";
type Service = { name: string; status: Verification; detail: string };
const labels: Record<Verification, string> = { VERIFIED: "Verificado", ERROR: "Con error", NOT_CONFIGURED: "No configurado", NOT_VERIFIED: "No verificado" };

export function SystemStatus({ services }: { services: Service[] }) {
  return <section className="h-full rounded-xl border border-line bg-surface-raised p-5"><div className="flex items-start gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><ServerCog className="size-5" /></span><div><div className="flex items-center gap-2"><h2 className="font-bold text-ink">Estado del sistema</h2><ContextHelp label="Ayuda sobre el estado del sistema" title="¿Cómo se determina este estado?">Cada indicador proviene de una comprobación ejecutada en el servidor o de una configuración verificable. Si Nodo no puede comprobar un servicio, lo informa sin asumir que está operativo.</ContextHelp></div><p className="mt-1 text-xs text-ink-muted">Comprobaciones básicas reales del entorno actual.</p></div></div><ul className="mt-5 divide-y divide-line border-t border-line">{services.map((service) => { const Icon = service.status === "VERIFIED" ? CircleCheck : service.status === "ERROR" ? CircleX : CircleDashed; return <li className="flex items-start justify-between gap-4 py-3" key={service.name}><div><strong className="text-sm text-ink">{service.name}</strong><p className="mt-1 text-xs text-ink-muted">{service.detail}</p></div><span className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold ${service.status === "VERIFIED" ? "bg-success-soft text-success" : service.status === "ERROR" ? "bg-danger-soft text-danger" : "bg-warning-soft text-warning"}`}><Icon className="size-3.5" />{labels[service.status]}</span></li>; })}</ul></section>;
}
