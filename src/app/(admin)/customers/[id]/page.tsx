import { ArrowLeft, Mail, MapPin, MessageCircle, Phone, Smartphone } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ButtonLink } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/PageHeader";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { getOrganizationCustomer } from "@/features/customers/repository";
import { deviceTypeLabels, getCustomerFullName } from "@/features/customers/types";
import { formatDateTime } from "@/lib/format";
import { listOrganizationRepairs } from "@/features/repairs/repository";
import { requireOwnerOrganization } from "@/lib/organizations/setup";

interface CustomerDetailPageProps { params: Promise<{ id: string }> }

export const metadata: Metadata = { title: "Cliente" };

export default async function CustomerDetailPage({ params }: CustomerDetailPageProps) {
  const { organization } = await requireOwnerOrganization();
  const { id } = await params;
  const [customer, organizationRepairs] = await Promise.all([getOrganizationCustomer(organization.id, id), listOrganizationRepairs(organization.id)]);
  if (!customer) notFound();
  const repairs = organizationRepairs.filter((repair) => repair.customerId === customer.id);

  return (
    <div className="space-y-6">
      <Link className="inline-flex items-center gap-2 text-sm font-bold text-muted hover:text-accent" href="/customers"><ArrowLeft className="size-4" />Volver a clientes</Link>
      <PageHeader eyebrow="Perfil del cliente" title={getCustomerFullName(customer)} description={`${customer.devices.length} equipos registrados · ${repairs.length} reparaciones asociadas`} actions={<ButtonLink href="/repairs/new">Nueva reparación</ButtonLink>} />
      <div className="grid gap-5 xl:grid-cols-[minmax(300px,0.7fr)_minmax(0,1.3fr)]">
        <div className="space-y-5">
          <Card className="p-5"><h2 className="font-bold text-primary">Datos personales</h2><dl className="mt-5 space-y-4 text-sm"><div className="flex gap-3"><Phone className="mt-0.5 size-4 text-accent" /><div><dt className="text-xs font-semibold text-muted">Teléfono</dt><dd className="mt-1 font-semibold text-primary">{customer.phone}</dd></div></div><div className="flex gap-3"><Mail className="mt-0.5 size-4 text-accent" /><div className="min-w-0"><dt className="text-xs font-semibold text-muted">Correo</dt><dd className="mt-1 break-all font-semibold text-primary">{customer.email}</dd></div></div>{customer.address ? <div className="flex gap-3"><MapPin className="mt-0.5 size-4 text-accent" /><div><dt className="text-xs font-semibold text-muted">Dirección</dt><dd className="mt-1 font-semibold text-primary">{customer.address}</dd></div></div> : null}<div className="flex gap-3"><MessageCircle className="mt-0.5 size-4 text-accent" /><div><dt className="text-xs font-semibold text-muted">Contacto preferido</dt><dd className="mt-1 font-semibold text-primary">{customer.preferredContact === "WHATSAPP" ? "WhatsApp" : customer.preferredContact === "PHONE" ? "Teléfono" : "Correo"}</dd></div></div></dl></Card>
          <Card className="p-5"><h2 className="font-bold text-primary">Historial resumido</h2>{customer.history.length ? <ol className="mt-5 space-y-4">{customer.history.map((item) => <li className="border-l-2 border-blue-200 pl-4" key={item.id}><strong className="text-sm text-primary">{item.title}</strong><p className="mt-1 text-xs leading-5 text-muted">{item.description}</p><time className="mt-1 block text-[11px] font-semibold text-slate-400">{formatDateTime(item.createdAt)}</time></li>)}</ol> : <p className="mt-4 text-sm text-muted">Todavía no hay eventos registrados.</p>}</Card>
        </div>
        <div className="space-y-5">
          <Card className="p-5"><div className="flex items-center justify-between"><h2 className="font-bold text-primary">Dispositivos</h2><span className="text-xs font-bold text-muted">{customer.devices.length} registrados</span></div><div className="mt-5 grid gap-3 sm:grid-cols-2">{customer.devices.map((device) => <article className="rounded-xl border border-border bg-surface-soft p-4" key={device.id}><span className="grid size-9 place-items-center rounded-lg bg-blue-50 text-accent"><Smartphone className="size-4" /></span><h3 className="mt-3 font-bold text-primary">{device.brand} {device.model}</h3><p className="mt-1 text-xs text-muted">{deviceTypeLabels[device.type]}{device.color ? ` · ${device.color}` : ""}</p>{device.serialNumber ? <p className="mt-3 text-xs font-semibold text-slate-500">Serie: {device.serialNumber}</p> : null}</article>)}</div></Card>
          <Card className="overflow-hidden"><div className="border-b border-border px-5 py-4"><h2 className="font-bold text-primary">Reparaciones</h2></div>{repairs.length ? <div className="divide-y divide-border">{repairs.map((repair) => <Link className="flex flex-col gap-3 px-5 py-4 hover:bg-slate-50 sm:flex-row sm:items-center sm:justify-between" href={`/repairs/${repair.id}`} key={repair.id}><div><p className="text-xs font-bold uppercase tracking-wide text-accent">{repair.orderNumber}</p><strong className="mt-1 block text-sm text-primary">{repair.device.brand} {repair.device.model}</strong><p className="mt-1 text-xs text-muted">{repair.reportedProblem}</p></div><StatusBadge compact status={repair.status} /></Link>)}</div> : <p className="p-5 text-sm text-muted">No hay reparaciones asociadas.</p>}</Card>
        </div>
      </div>
    </div>
  );
}
