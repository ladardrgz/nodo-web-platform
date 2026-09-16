"use client";

import { UserRound } from "lucide-react";
import { cn } from "@/lib/cn";
import { calculateCondition } from "@/features/repairs/reception/inspection";
import type { DeviceDraft, ReceptionCustomer } from "@/features/repairs/reception/types";
import type { CustomerDraft } from "@/features/repairs/reception/wizard-types";

export function ConfirmationStep({
  customerName,
  customer,
  typeName,
  brandName,
  device,
  condition,
  reportedProblem,
  accessoryNames,
  termsAccepted,
  setTermsAccepted,
  error,
}: {
  customerName: string;
  customer: CustomerDraft | ReceptionCustomer;
  typeName: string;
  brandName: string;
  device: DeviceDraft;
  condition: ReturnType<typeof calculateCondition>;
  reportedProblem: string;
  accessoryNames: string[];
  termsAccepted: boolean;
  setTermsAccepted: (value: boolean) => void;
  error?: string;
}) {
  return (
    <fieldset>
      <legend className="text-xl font-bold text-primary">
        4. Confirmación
      </legend>
      <p className="mt-2 text-sm text-muted">
        Revisá la información antes de congelar el snapshot original de
        recepción.
      </p>
      <div className="mt-6 rounded-xl border border-line bg-surface-soft p-5">
        <div className="flex items-center gap-3">
          <span className="grid size-10 place-items-center rounded-full bg-accent-soft text-accent">
            <UserRound className="size-5" />
          </span>
          <div>
            <strong className="text-primary">{customerName}</strong>
            <p className="text-xs text-muted">
              {customer.phone}
              {customer.email ? ` · ${customer.email}` : ""}
            </p>
          </div>
        </div>
        <dl className="mt-5 grid gap-4 border-t border-line pt-5 sm:grid-cols-2">
          <SummaryRow label="Equipo" value={`${brandName} ${device.model}`} />
          <SummaryRow label="Tipo" value={typeName} />
          <SummaryRow
            label="Estado físico calculado"
            value={`${condition.label} (${condition.score} puntos)`}
          />
          <SummaryRow
            label="Accesorios"
            value={accessoryNames.join(", ") || "Ninguno"}
          />
        </dl>
        <div className="mt-4">
          <p className="text-xs font-bold uppercase tracking-wide text-muted">
            Problema informado
          </p>
          <p className="mt-1 text-sm leading-6 text-primary">
            {reportedProblem}
          </p>
        </div>
      </div>
      <label
        className={cn(
          "mt-5 flex cursor-pointer items-start gap-3 rounded-lg border bg-surface p-4",
          error ? "border-danger" : "border-line",
        )}
      >
        <input
          checked={termsAccepted}
          className="mt-0.5 size-5 accent-blue-600"
          onChange={(event) => setTermsAccepted(event.target.checked)}
          type="checkbox"
        />
        <span className="text-sm leading-6 text-primary">
          Confirmo que los datos fueron revisados con el cliente. Esta acción
          conservará la recepción original como evidencia histórica.
        </span>
      </label>
      {error && <p className="mt-1.5 text-sm text-danger">{error}</p>}
    </fieldset>
  );
}
// PASO 4 · CONFIRMACIÓN — Fila reutilizable del resumen final.
function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs font-bold uppercase tracking-wide text-muted">
        {label}
      </dt>
      <dd className="mt-1 text-sm font-semibold text-primary">{value}</dd>
    </div>
  );
}
