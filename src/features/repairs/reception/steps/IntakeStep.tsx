"use client";

/* Blob URLs are local previews and cannot benefit from Next image optimization. */
/* eslint-disable @next/next/no-img-element */

import { AlertTriangle, Camera, Plus, Trash2 } from "lucide-react";
import type { ChangeEvent, Dispatch, SetStateAction } from "react";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { cn } from "@/lib/cn";
import { calculateCondition, INSPECTION_STATUSES } from "@/features/repairs/reception/inspection";
import type { CatalogOption, EvidenceDraft, InspectionItemDraft, IntakeMetadata } from "@/features/repairs/reception/types";
import type { WizardErrors } from "@/features/repairs/reception/wizard-types";

export function IntakeStep({
  inspection,
  setInspection,
  condition,
  reportedProblem,
  setReportedProblem,
  observations,
  setObservations,
  intakeMetadata,
  setIntakeMetadata,
  photos,
  setPhotos,
  addPhotos,
  errors,
  deviceTypeCode,
  accessories,
}: {
  inspection: InspectionItemDraft[];
  setInspection: Dispatch<SetStateAction<InspectionItemDraft[]>>;
  condition: ReturnType<typeof calculateCondition>;
  reportedProblem: string;
  setReportedProblem: (value: string) => void;
  observations: string;
  setObservations: (value: string) => void;
  intakeMetadata: IntakeMetadata;
  setIntakeMetadata: Dispatch<SetStateAction<IntakeMetadata>>;
  photos: EvidenceDraft[];
  setPhotos: Dispatch<SetStateAction<EvidenceDraft[]>>;
  addPhotos: (event: ChangeEvent<HTMLInputElement>) => void;
  errors: WizardErrors;
  deviceTypeCode?: string;
  accessories: CatalogOption[];
}) {
  // PASO 3 · INSPECCIÓN — Actualiza únicamente el ítem modificado.
  const updateItem = (index: number, patch: Partial<InspectionItemDraft>) =>
    setInspection((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index ? { ...item, ...patch } : item,
      ),
    );
  return (
    <fieldset>
      <legend className="text-xl font-bold text-primary">
        3. Recepción del equipo
      </legend>
      <p className="mt-2 text-sm text-muted">
        Separá lo informado por el cliente de lo observado físicamente al
        ingresar.
      </p>
      <div className="mt-6 space-y-7">
        <section className="rounded-xl border border-line bg-surface-soft p-4">
          <h3 className="font-bold text-primary">Estado inicial y acceso</h3>
          <p className="mt-1 text-sm text-muted">No se almacena ningún PIN, patrón ni contraseña.</p>
          <div className="mt-4 grid gap-4 md:grid-cols-3">
            <ReceptionSelect label="Encendido" value={intakeMetadata.powerState} onChange={(powerState) => setIntakeMetadata((current) => ({ ...current, powerState: powerState as IntakeMetadata["powerState"] }))} options={[["POWERS_ON","Enciende"],["DOES_NOT_POWER_ON","No enciende"],["NOT_TESTED","No probado"]]} />
            <ReceptionSelect label="Imagen" value={intakeMetadata.imageState} onChange={(imageState) => setIntakeMetadata((current) => ({ ...current, imageState: imageState as IntakeMetadata["imageState"] }))} options={[["HAS_IMAGE","Da imagen"],["NO_IMAGE","No da imagen"],["NOT_TESTED","No probado"],["NOT_APPLICABLE","No aplica"]]} />
            <ReceptionSelect label="Carga" value={intakeMetadata.chargeState} onChange={(chargeState) => setIntakeMetadata((current) => ({ ...current, chargeState: chargeState as IntakeMetadata["chargeState"] }))} options={[["CHARGES","Carga correctamente"],["INTERMITTENT","Carga intermitente"],["DOES_NOT_CHARGE","No carga"],["NOT_TESTED","No probado"]]} />
          </div>
          <div className="mt-4 grid gap-4 md:grid-cols-2">
            <ReceptionSelect label="¿Cliente deja desbloqueado el dispositivo?" value={intakeMetadata.accessAvailable} onChange={(accessAvailable) => setIntakeMetadata((current) => ({ ...current, accessAvailable: accessAvailable as IntakeMetadata["accessAvailable"], accessMethod: accessAvailable === "true" ? current.accessMethod : "", credentialProvided: accessAvailable === "true" ? current.credentialProvided : false }))} options={[["true","Sí"],["false","No"]]} />
            {intakeMetadata.accessAvailable === "true" ? <ReceptionSelect label="Método de acceso declarado" value={intakeMetadata.accessMethod} onChange={(accessMethod) => setIntakeMetadata((current) => ({ ...current, accessMethod: accessMethod as IntakeMetadata["accessMethod"], credentialProvided: accessMethod !== "UNLOCKED" }))} options={[["UNLOCKED","Se entrega desbloqueado"],["PIN","PIN entregado por canal seguro"],["PATTERN","Patrón entregado por canal seguro"],["PASSWORD","Contraseña entregada por canal seguro"],["BIOMETRIC","Biometría"],["OTHER","Otro"]]} /> : null}
          </div>
          {deviceTypeCode === "desktop_pc" ? <div className="mt-5 border-t border-line pt-5">
            <h4 className="font-semibold text-primary">Prueba rápida de la torre</h4>
            <p className="mt-1 text-xs leading-5 text-muted">Registrá sólo lo que se comprobó de forma segura. Esto no reemplaza el diagnóstico.</p>
            <div className="mt-4 grid gap-4 md:grid-cols-3">
              <ReceptionSelect label="POST" value={intakeMetadata.postState} onChange={(postState) => setIntakeMetadata((current) => ({ ...current, postState: postState as IntakeMetadata["postState"] }))} options={[["COMPLETES","Completa POST"],["DOES_NOT_COMPLETE","No completa POST"],["UNDETERMINED","No determinado"],["NOT_TESTED","No probado"],["NOT_APPLICABLE","No aplica"]]} />
              <ReceptionSelect label="Sistema operativo" value={intakeMetadata.osBootState} onChange={(osBootState) => setIntakeMetadata((current) => ({ ...current, osBootState: osBootState as IntakeMetadata["osBootState"] }))} options={[["BOOTS","Inicia"],["DOES_NOT_BOOT","No inicia"],["NOT_TESTED","No probado"],["NO_OS","Sin sistema operativo"],["NOT_APPLICABLE","No aplica"]]} />
              <ReceptionSelect label="Inventario interno" value={intakeMetadata.inventoryStatus} onChange={(inventoryStatus) => setIntakeMetadata((current) => ({ ...current, inventoryStatus: inventoryStatus as IntakeMetadata["inventoryStatus"] }))} options={[["COMPLETE","Completo"],["PARTIAL","Parcial"],["NOT_PERFORMED","No realizado"]]} />
            </div>
            {intakeMetadata.powerState === "NOT_TESTED" ? <FormField htmlFor="powerTestReason" label="Motivo de no energizar" hint="Ej. Riesgo por líquido, olor a quemado o daño eléctrico visible."><input className="field-control" id="powerTestReason" maxLength={300} onChange={(event) => setIntakeMetadata((current) => ({ ...current, powerTestReason: event.target.value }))} value={intakeMetadata.powerTestReason} /></FormField> : null}
          </div> : null}
        </section>
        <FormField
          error={errors.reportedProblem}
          hint="Registrá lo que declara el cliente; no es un diagnóstico técnico."
          htmlFor="reportedProblem"
          label="Problema informado"
          required
        >
          <textarea
            className={cn(
              "field-control min-h-28 resize-y",
              errors.reportedProblem && "field-control-invalid",
            )}
            id="reportedProblem"
            maxLength={2000}
            onChange={(event) => setReportedProblem(event.target.value)}
            placeholder="El cliente informa que el equipo…"
            value={reportedProblem}
          />
        </FormField>
        <section>
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h3 className="font-bold text-primary">
                Inspección física de recepción
              </h3>
              <p className="mt-1 text-sm text-muted">
                Completá cada ítem según lo que puede observarse ahora.
              </p>
            </div>
            <div className="rounded-lg border border-accent/30 bg-accent-soft px-4 py-2 text-sm">
              <span className="text-muted">Estado físico calculado:</span>{" "}
              <strong className="text-primary">{condition.label}</strong>
              <span className="ml-2 text-xs text-muted">
                ({condition.score} ptos.)
              </span>
            </div>
          </div>
          {errors.inspection && (
            <p className="mt-2 text-sm font-medium text-danger">
              {errors.inspection}
            </p>
          )}
          <div className="mt-4 divide-y divide-line rounded-xl border border-line">
            {inspection.map((item, index) => {
              const critical = condition.critical.some(
                (entry) => entry.key === item.key,
              );
              return (
                <div
                  className={cn(
                    "grid gap-3 p-4 lg:grid-cols-[minmax(160px,.8fr)_minmax(180px,.65fr)_minmax(220px,1fr)] lg:items-center",
                    critical && "bg-danger-soft/50",
                  )}
                  key={item.key}
                >
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-primary">
                      {item.label}
                    </span>
                    {critical && (
                      <AlertTriangle className="size-4 text-danger" />
                    )}
                  </div>
                  <select
                    aria-label={`Estado de ${item.label}`}
                    className="field-control"
                    onChange={(event) =>
                      updateItem(index, {
                        status: event.target
                          .value as InspectionItemDraft["status"],
                      })
                    }
                    value={item.status}
                  >
                    <option value="">Seleccionar estado</option>
                    {Object.entries(INSPECTION_STATUSES).filter(([value]) => deviceTypeCode !== "cell_phone" || ["NO_DAMAGE","NOT_WORKING","NOT_VERIFIABLE","NOT_APPLICABLE"].includes(value)).map(
                      ([value, config]) => (
                        <option key={value} value={value}>
                          {deviceTypeCode === "cell_phone" ? ({ NO_DAMAGE: "OK", NOT_WORKING: "Falla", NOT_VERIFIABLE: "No probado", NOT_APPLICABLE: "No aplica" } as Record<string,string>)[value] : config.label}
                        </option>
                      ),
                    )}
                  </select>
                  <input
                    aria-label={`Observación de ${item.label}`}
                    className="field-control"
                    maxLength={500}
                    onChange={(event) =>
                      updateItem(index, { observation: event.target.value })
                    }
                    placeholder="Observación opcional"
                    value={item.observation}
                  />
                </div>
              );
            })}
          </div>
          {condition.critical.length > 0 && (
            <div className="mt-3 flex gap-2 rounded-lg border border-danger/30 bg-danger-soft p-3 text-sm text-danger">
              <AlertTriangle className="mt-0.5 size-4 shrink-0" />
              <span>
                <strong>Daños importantes:</strong>{" "}
                {condition.critical.map((item) => item.label).join(", ")}.
              </span>
            </div>
          )}
        </section>
        <PhotoEvidence
          photos={photos}
          setPhotos={setPhotos}
          inspection={inspection}
          addPhotos={addPhotos}
          error={errors.photos}
        />
        <section className="rounded-xl border border-line bg-surface-soft p-4">
          <div className="flex flex-wrap items-center justify-between gap-3"><div><h3 className="font-bold text-primary">Elementos entregados en esta recepción</h3><p className="mt-1 text-sm text-muted">Diferenciá accesorios, periféricos y componentes sueltos del hardware instalado.</p></div><Button onClick={() => setIntakeMetadata((current) => ({ ...current, receptionItems: [...current.receptionItems, { accessoryId: "", role: "ACCESSORY", quantity: "1", description: "", observation: "" }] }))} size="sm" variant="secondary"><Plus className="size-4" />Agregar elemento</Button></div>
          {intakeMetadata.receptionItems.length ? <div className="mt-4 space-y-3">{intakeMetadata.receptionItems.map((item,index) => <div className="grid gap-3 rounded-lg border border-line bg-surface p-3 md:grid-cols-[1fr_.7fr_90px_1fr_auto]" key={index}>
            <select aria-label={`Elemento ${index+1}`} className="field-control" onChange={(event) => setIntakeMetadata((current) => ({ ...current, receptionItems: current.receptionItems.map((entry,position) => position===index ? { ...entry, accessoryId:event.target.value } : entry) }))} value={item.accessoryId ?? ""}><option value="">Descripción manual</option>{accessories.map((entry) => <option key={entry.id} value={entry.id}>{entry.name}</option>)}</select>
            <select aria-label={`Rol del elemento ${index+1}`} className="field-control" onChange={(event) => setIntakeMetadata((current) => ({ ...current, receptionItems: current.receptionItems.map((entry,position) => position===index ? { ...entry, role:event.target.value as IntakeMetadata["receptionItems"][number]["role"] } : entry) }))} value={item.role}><option value="ACCESSORY">Accesorio</option><option value="PERIPHERAL">Periférico</option><option value="LOOSE_COMPONENT">Componente suelto</option><option value="OTHER">Otro</option></select>
            <input aria-label={`Cantidad del elemento ${index+1}`} className="field-control" min="1" onChange={(event) => setIntakeMetadata((current) => ({ ...current, receptionItems: current.receptionItems.map((entry,position) => position===index ? { ...entry, quantity:event.target.value } : entry) }))} type="number" value={item.quantity} />
            <input aria-label={`Descripción del elemento ${index+1}`} className="field-control" maxLength={200} onChange={(event) => setIntakeMetadata((current) => ({ ...current, receptionItems: current.receptionItems.map((entry,position) => position===index ? { ...entry, description:event.target.value } : entry) }))} placeholder="Descripción, color o detalle" value={item.description ?? ""} />
            <Button aria-label={`Quitar elemento ${index+1}`} onClick={() => setIntakeMetadata((current) => ({ ...current, receptionItems: current.receptionItems.filter((_,position) => position!==index) }))} size="sm" variant="ghost"><Trash2 className="size-4" /></Button>
          </div>)}</div> : <p className="mt-4 rounded-lg border border-dashed border-line p-4 text-center text-sm text-muted">No se registraron elementos entregados.</p>}
        </section>
        <FormField
          htmlFor="observations"
          label="Observaciones de recepción"
          hint="Notas adicionales que no correspondan al problema informado ni a un ítem concreto."
        >
          <textarea
            className="field-control min-h-24 resize-y"
            id="observations"
            maxLength={2000}
            onChange={(event) => setObservations(event.target.value)}
            placeholder="Ej. El equipo fue entregado apagado y sin cargador."
            value={observations}
          />
        </FormField>
      </div>
    </fieldset>
  );
}

function ReceptionSelect({ label, value, options, onChange }: { label: string; value: string; options: Array<[string,string]>; onChange: (value: string) => void }) {
  return <label className="text-sm font-semibold text-primary">{label}<select className="field-control mt-2" onChange={(event) => onChange(event.target.value)} value={value}><option value="">Sin informar</option>{options.map(([optionValue, optionLabel]) => <option key={optionValue} value={optionValue}>{optionLabel}</option>)}</select></label>;
}

// --------------------------------------------------------------------------
// PASO 3 · EVIDENCIA FOTOGRÁFICA
// Administra vista previa, asociación con un ítem inspeccionado, descripción
// y eliminación local antes de confirmar la recepción.
// --------------------------------------------------------------------------
function PhotoEvidence({
  photos,
  setPhotos,
  inspection,
  addPhotos,
  error,
}: {
  photos: EvidenceDraft[];
  setPhotos: Dispatch<SetStateAction<EvidenceDraft[]>>;
  inspection: InspectionItemDraft[];
  addPhotos: (event: ChangeEvent<HTMLInputElement>) => void;
  error?: string;
}) {
  const update = (id: string, patch: Partial<EvidenceDraft>) =>
    setPhotos((current) =>
      current.map((photo) =>
        photo.id === id ? { ...photo, ...patch } : photo,
      ),
    );
  return (
    <section className="rounded-xl border border-line bg-surface-soft p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="font-bold text-primary">Evidencia fotográfica</h3>
          <p className="mt-1 text-xs text-muted">
            PNG, JPG o WebP · máximo 5 MB por fotografía.
          </p>
        </div>
        <label className="inline-flex min-h-10 cursor-pointer items-center gap-2 rounded-lg bg-accent-button px-4 text-sm font-semibold text-white hover:bg-accent-button-hover">
          <Camera className="size-4" />
          Agregar fotografías
          <input
            accept="image/png,image/jpeg,image/webp"
            className="sr-only"
            multiple
            onChange={addPhotos}
            type="file"
          />
        </label>
      </div>
      {error && <p className="mt-2 text-sm font-medium text-danger">{error}</p>}
      {photos.length ? (
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {photos.map((photo) => (
            <article
              className="overflow-hidden rounded-xl border border-line bg-surface"
              key={photo.id}
            >
              <div className="aspect-video bg-surface-soft">
                <img
                  alt="Vista previa de evidencia de recepción"
                  className="size-full object-contain"
                  src={photo.previewUrl}
                />
              </div>
              <div className="space-y-3 p-3">
                <select
                  aria-label="Elemento inspeccionado asociado"
                  className="field-control"
                  onChange={(event) =>
                    update(photo.id, { inspectionKey: event.target.value })
                  }
                  value={photo.inspectionKey}
                >
                  <option value="">Sin asociación específica</option>
                  {inspection.map((item) => (
                    <option key={item.key} value={item.key}>
                      {item.label}
                    </option>
                  ))}
                </select>
                <input
                  aria-label="Descripción de la fotografía"
                  className="field-control"
                  maxLength={300}
                  onChange={(event) =>
                    update(photo.id, { description: event.target.value })
                  }
                  placeholder="Descripción opcional"
                  value={photo.description}
                />
                <Button
                  className="w-full"
                  onClick={() => {
                    URL.revokeObjectURL(photo.previewUrl);
                    setPhotos((current) =>
                      current.filter((item) => item.id !== photo.id),
                    );
                  }}
                  size="sm"
                  variant="ghost"
                >
                  <Trash2 className="size-4" />
                  Quitar selección
                </Button>
              </div>
            </article>
          ))}
        </div>
      ) : (
        <p className="mt-4 rounded-lg border border-dashed border-line p-5 text-center text-sm text-muted">
          Todavía no agregaste fotografías.
        </p>
      )}
    </section>
  );
}
