"use client";

import { AlertCircle, CheckCircle2, Edit3, Info, Mail, MapPin, Phone, X } from "lucide-react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useId, useRef, useState, type ReactNode } from "react";
import { formatPhoneNumberIntl } from "react-phone-number-input";

import { useToast } from "@/components/feedback/ToastProvider";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import {
  finalizeInitialSetupAction,
  initialFinalizeInitialSetupState,
  type FinalizeInitialSetupState,
  type IncompleteSetupSection,
} from "@/features/organizations/finalize-setup-action";
import { getOrganizationDisplayName } from "@/lib/organizations/display-name";
import { cn } from "@/lib/cn";
import type { InitialSetupConfirmationData } from "@/types/geography";
import type { OwnerOrganization } from "@/types/organization";

function SummaryCard({
  children,
  incomplete,
  onEdit,
  title,
}: {
  children: ReactNode;
  incomplete: boolean;
  onEdit: () => void;
  title: string;
}) {
  return (
    <article className={cn("rounded-xl border bg-surface-raised p-4 sm:p-5", incomplete ? "border-warning" : "border-line")}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-bold text-ink">{title}</h3>
          {incomplete ? <p className="mt-1 flex items-center gap-1.5 text-xs font-semibold text-warning"><AlertCircle className="size-3.5" />Información incompleta</p> : null}
        </div>
        <Button aria-label={`${incomplete ? "Completar" : "Editar"} ${title}`} onClick={onEdit} size="sm" variant="ghost">
          <Edit3 aria-hidden="true" className="size-4" />{incomplete ? "Completar datos" : "Editar"}
        </Button>
      </div>
      <div className="mt-4">{children}</div>
    </article>
  );
}

interface OrganizationStepFourConfirmationProps {
  confirmationData: InitialSetupConfirmationData;
  logoUrl: string | null;
  onBack: () => void;
  onEdit: (step: 0 | 1 | 2) => void;
  organization: OwnerOrganization;
}

export function OrganizationStepFourConfirmation({ confirmationData, logoUrl, onBack, onEdit, organization }: OrganizationStepFourConfirmationProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [open, setOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const submittingRef = useRef(false);
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const displayName = getOrganizationDisplayName(organization);
  const phoneDisplay = confirmationData.phoneDisplay
    ? formatPhoneNumberIntl(confirmationData.phoneDisplay) || confirmationData.phoneDisplay
    : null;
  const initials = displayName.split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "N";
  const [state, action] = useActionState(async (previous: FinalizeInitialSetupState, formData: FormData) => {
    const next = await finalizeInitialSetupAction(previous, formData);
    setSubmitting(false);
    submittingRef.current = false;
    if (next.status === "success") {
      router.push("/dashboard?setup=organization_setup_completed");
    } else if (next.feedback) {
      toast(next.feedback);
    }
    return { ...next, feedback: undefined };
  }, initialFinalizeInitialSetupState);

  useEffect(() => {
    // Al entrar a Confirmación vuelve a leer Server Components para evitar snapshots del paso anterior.
    router.refresh();
  }, [router]);

  const closeModal = () => {
    if (submittingRef.current) return;
    setOpen(false);
  };

  useEffect(() => {
    if (!open) return;
    dialogRef.current?.querySelector<HTMLElement>("button:not(:disabled)")?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !submittingRef.current) {
        event.preventDefault();
        setOpen(false);
        return;
      }
      if (event.key !== "Tab") return;
      const focusable = Array.from(dialogRef.current?.querySelectorAll<HTMLElement>("button:not(:disabled), [href], input:not(:disabled)") ?? []);
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable.at(-1)!;
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [open]);

  const incomplete = (section: IncompleteSetupSection) => state.incompleteSection === section;

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-xl font-bold text-ink">Revisá tu configuración</h3>
        <p className="mt-2 text-sm leading-6 text-ink-muted">Verificá que los datos de tu organización sean correctos antes de habilitar tu espacio de trabajo.</p>
      </div>

      <div className="grid gap-4 xl:grid-cols-3">
        <SummaryCard incomplete={incomplete("ORGANIZATION")} onEdit={() => onEdit(0)} title="Organización">
          <div className="flex items-center gap-3">
            <div className="relative grid size-14 shrink-0 place-items-center overflow-hidden rounded-xl border border-line bg-surface-soft text-sm font-bold text-accent">
              {logoUrl ? <Image alt={`Logo de ${displayName}`} className="object-contain p-1.5" fill sizes="56px" src={logoUrl} unoptimized /> : initials}
            </div>
            <div className="min-w-0"><strong className="block truncate text-base text-ink">{displayName || "Sin nombre comercial"}</strong><p className="mt-1 text-sm text-ink-muted">{organization.name || "Sin razón social"}</p></div>
          </div>
        </SummaryCard>

        <SummaryCard incomplete={incomplete("CONTACT")} onEdit={() => onEdit(1)} title="Contacto">
          <dl className="space-y-3 text-sm">
            <div className="flex items-start gap-2.5"><Phone aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-accent" /><div><dt className="sr-only">Teléfono</dt><dd className="text-ink">{phoneDisplay || "No informado"}</dd></div></div>
            <div className="flex min-w-0 items-start gap-2.5"><Mail aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-accent" /><div className="min-w-0"><dt className="sr-only">Email de contacto</dt><dd className="break-all text-ink">{organization.contact_email || "No informado"}</dd></div></div>
          </dl>
        </SummaryCard>

        <SummaryCard incomplete={incomplete("LOCATION")} onEdit={() => onEdit(2)} title="Ubicación">
          <div className="flex items-start gap-2.5"><MapPin aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-accent" /><p className="text-sm leading-6 text-ink">{confirmationData.formattedAddress || "No informada"}</p></div>
        </SummaryCard>
      </div>

      <div className="flex items-start gap-3 rounded-xl border border-accent/25 bg-accent-soft p-4">
        <Info aria-hidden="true" className="mt-0.5 size-5 shrink-0 text-accent" />
        <p className="text-sm leading-6 text-ink-secondary">Al finalizar, Nodo habilitará las funciones operativas de tu espacio de trabajo. Podrás modificar estos datos más adelante desde Configuración.</p>
      </div>

      <div className="flex flex-col-reverse gap-3 border-t border-line pt-5 sm:flex-row sm:items-center sm:justify-between">
        <Button className="w-full sm:w-auto" onClick={onBack} variant="secondary">Volver</Button>
        <Button className="w-full sm:w-auto" onClick={() => setOpen(true)}><CheckCircle2 aria-hidden="true" className="size-4" />Finalizar configuración</Button>
      </div>

      {open ? (
        <div className="fixed inset-0 z-[80] flex items-start justify-center overflow-y-auto bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) closeModal(); }}>
          <div aria-labelledby={titleId} aria-modal="true" className="w-full max-w-lg rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" ref={dialogRef} role="dialog">
            <div className="flex items-start justify-between gap-3"><div><h2 className="text-lg font-bold text-ink" id={titleId}>¿Finalizar configuración?</h2><p className="mt-2 text-sm leading-6 text-ink-secondary">Confirmá que revisaste los datos de tu organización. Al continuar, se habilitarán las funciones principales de Nodo.</p></div><button aria-label="Cerrar" className="grid size-8 shrink-0 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft hover:text-ink disabled:opacity-50" disabled={submitting} onClick={closeModal} type="button"><X className="size-4" /></button></div>
            <dl className="mt-5 rounded-lg bg-surface-soft p-4 text-sm"><div className="flex items-center justify-between gap-4"><dt className="text-ink-muted">Organización</dt><dd className="text-right font-semibold text-ink">{displayName}</dd></div></dl>
            <form action={action} className="mt-5" onSubmit={() => { submittingRef.current = true; setSubmitting(true); }}>
              <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button disabled={submitting} onClick={closeModal} variant="secondary">Cancelar</Button><SubmitButton label="Confirmar y comenzar" pendingLabel="Configurando Nodo..." /></div>
            </form>
          </div>
        </div>
      ) : null}
    </div>
  );
}
