"use client";

import {
  Check,
  ChevronLeft,
  ChevronRight,
  ClipboardCheck,
} from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { useToast } from "@/components/feedback/ToastProvider";
import { cn } from "@/lib/cn";
import {
  createCustomerAction,
  createCustomBrandAction,
  createCustomDeviceColorAction,
  createCustomDeviceModelAction,
  createCustomDeviceTypeAction,
  createDynamicCatalogOptionAction,
  saveDeviceAction,
  confirmReceptionAction,
} from "@/features/repairs/reception/actions";
import { calculateCondition } from "@/features/repairs/reception/inspection";
import { CatalogModal } from "@/features/repairs/reception/CatalogModal";
import { WIZARD_STEPS } from "@/features/repairs/reception/constants/reception";
import { validateDevice as validateDeviceDraft } from "@/features/repairs/reception/validation/deviceValidation";
import { validateReception } from "@/features/repairs/reception/validation/receptionValidation";
import { useCustomerStep } from "@/features/repairs/reception/hooks/useCustomerStep";
import { useDeviceCatalogs } from "@/features/repairs/reception/hooks/useDeviceCatalogs";
import { useReceptionPhotos } from "@/features/repairs/reception/hooks/useReceptionPhotos";
import { CustomerStep } from "@/features/repairs/reception/steps/CustomerStep";
import { DeviceStep } from "@/features/repairs/reception/steps/DeviceStep";
import { IntakeStep } from "@/features/repairs/reception/steps/IntakeStep";
import { ConfirmationStep } from "@/features/repairs/reception/steps/ConfirmationStep";
import type {
  DeviceModelOption,
  DeviceColorOption,
  DeviceDraft,
  DeviceStepTwoSnapshot,
  DynamicDeviceField,
  InspectionItemDraft,
  IntakeMetadata,
  ReceptionFormData,
} from "@/features/repairs/reception/types";
import type { WizardErrors } from "@/features/repairs/reception/wizard-types";

type DynamicCatalogRequest = {
  sourceKey: NonNullable<DynamicDeviceField["dataSourceKey"]>;
  fieldKey?: string;
  parentId?: string;
  grandparentId?: string;
  storageIndex?: number;
  accessory?: boolean;
};

// ============================================================================
// CONFIGURACIÓN GENERAL DEL FLUJO DE RECEPCIÓN
// Pasos visibles del formulario y restricciones globales de fotografías.
// ============================================================================
const initialDevice: DeviceDraft = {
  typeId: "",
  attributeGroup: "OTHER",
  brandId: "",
  modelId: "",
  model: "",
  year: "",
  color: "",
  customColor: "",
  serialNumber: "",
  imei1: "",
  imei2: "",
  imeis: [],
  attributes: {},
  memories: [],
  storageUnits: [],
  accessories: [],
  ports: [],
};
// ============================================================================
// FORMULARIO PRINCIPAL DE NUEVA RECEPCIÓN
// Coordina los 4 pasos, las validaciones, persistencia y confirmación final.
// ============================================================================
export function NewRepairForm({
  initialData,
  initialSnapshot,
}: {
  initialData: ReceptionFormData;
  initialSnapshot?: DeviceStepTwoSnapshot;
}) {
  const { toast } = useToast();

  // --------------------------------------------------------------------------
  // ESTADO GENERAL DEL WIZARD
  // step: 0 = Cliente · 1 = Dispositivo · 2 = Recepción · 3 = Confirmación
  // --------------------------------------------------------------------------
  const [step, setStep] = useState(0);
  const [types, setTypes] = useState(initialData.deviceTypes);
  const [, setColors] = useState(initialData.deviceColors);
  const [accessories, setAccessories] = useState(initialData.accessories);
  const [device, setDevice] = useState<DeviceDraft>(initialDevice);
  const [deviceId, setDeviceId] = useState("");
  const [inspection, setInspection] = useState<InspectionItemDraft[]>([]);
  const [reportedProblem, setReportedProblem] = useState("");
  const [observations, setObservations] = useState("");
  const [intakeMetadata, setIntakeMetadata] = useState<IntakeMetadata>({ powerState: "", imageState: "", chargeState: "", accessAvailable: "", accessMethod: "", credentialProvided: false, postState: "", osBootState: "", inventoryStatus: "", powerTestReason: "", receptionItems: [] });
  const [errors, setErrors] = useState<WizardErrors>({});
  const [busy, setBusy] = useState(false);
  const [completed, setCompleted] = useState(false);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [modal, setModal] = useState<
    "type" | "brand" | "model" | "color" | null
  >(null);
  const [dynamicModal, setDynamicModal] =
    useState<DynamicCatalogRequest | null>(null);
  const [modalError, setModalError] = useState<string>();
  const setFieldError = (key: string, value?: string) =>
    setErrors((current) => ({ ...current, [key]: value }));
  const { customers, setCustomers, customerId, setCustomerId, customer, setTouched, chooseCustomer, updateCustomer, validateCustomer } =
    useCustomerStep(initialData.customers, setErrors);
  const { brands, setBrands, models, setModels, variants, brandCatalogState, modelCatalogState, variantCatalogState, fieldCatalogs, setFieldCatalogs, processorCatalogStates, processorCatalogErrors, chooseType, chooseBrand: chooseCatalogBrand, chooseModel, chooseTechnicalField } =
    useDeviceCatalogs({ initialData, types, setDevice, setInspection, setFieldError });
  const { photos, setPhotos, addPhotos, uploadPhotos, disposePhotos } =
    useReceptionPhotos({
      setFieldError,
      notify: (message, variant) => toast({ variant, title: message }),
    });
  const selectedType = types.find((item) => item.id === device.typeId);
  const selectedBrand = brands.find((item) => item.id === device.brandId);
  const selectedCustomer = customers.find((item) => item.id === customerId);
  const condition = useMemo(() => calculateCondition(inspection), [inspection]);
  const customerName = selectedCustomer
    ? `${selectedCustomer.firstName} ${selectedCustomer.lastName}`
    : `${customer.firstName} ${customer.lastName}`.trim();
  const chooseBrand = (id: string) => chooseCatalogBrand(id, device.typeId);
  const hydratedEdit = useRef(false);

  useEffect(() => {
    if (!initialSnapshot || hydratedEdit.current) return;
    hydratedEdit.current = true;
    const hydrate = async () => {
      const draft = initialSnapshot.device;
      chooseCustomer(initialSnapshot.customerId);
      await chooseType(draft.typeId);
      await chooseCatalogBrand(draft.brandId, draft.typeId);
      await chooseModel(draft.modelId);
      const typeCode = initialData.deviceTypes.find((item) => item.id === draft.typeId)?.code;
      const attrs = draft.attributes;
      if (attrs.processor_brand_id) await chooseTechnicalField("processor_brand_id", attrs.processor_brand_id, typeCode, attrs);
      if (attrs.processor_family_id) await chooseTechnicalField("processor_family_id", attrs.processor_family_id, typeCode, attrs);
      if (attrs.processor_generation_id) await chooseTechnicalField("processor_generation_id", attrs.processor_generation_id, typeCode, attrs);
      setDevice(draft);
      setDeviceId(draft.deviceId ?? "");
      setStep(1);
    };
    void hydrate();
  }, [initialSnapshot, initialData.deviceTypes, chooseCatalogBrand, chooseCustomer, chooseModel, chooseTechnicalField, chooseType]);

  // PASO 1 · CLIENTE — PERSISTENCIA Y AVANCE AL PASO 2
  // Si el cliente ya existe avanza directamente; si es nuevo, lo crea primero.
  async function completeCustomerStep() {
    if (!validateCustomer()) return;
    if (customerId !== "NEW") {
      setStep(1);
      return;
    }
    setBusy(true);
    const result = await createCustomerAction(customer);
    setBusy(false);
    if (!result.ok) {
      setErrors((current) => ({ ...current, ...result.fieldErrors }));
      toast({ variant: "error", title: result.message });
      return;
    }
    setCustomers((current) => [...current, result.data]);
    setCustomerId(result.data.id);
    toast({ variant: "success", title: result.message });
    setStep(1);
  }



  // PASO 2 · DISPOSITIVO — VALIDACIONES ANTES DE GUARDAR
  // Tipo, marca y modelo son obligatorios. El año, si existe, debe tener 4 dígitos.
  function validateDevice() {
    const next = validateDeviceDraft(device, selectedType?.code);
    setErrors(next);
    return !Object.values(next).some(Boolean);
  }
  // PASO 2 · DISPOSITIVO — PERSISTENCIA Y AVANCE AL PASO 3
  async function completeDeviceStep() {
    if (!validateDevice()) return;
    setBusy(true);
    const color =
      device.color === "Otro color" ? device.customColor.trim() : device.color;
    const result = await saveDeviceAction({ customerId, ...device, color });
    setBusy(false);
    if (!result.ok) {
      setErrors(result.fieldErrors ?? {});
      toast({ variant: "error", title: result.message });
      return;
    }
    setDeviceId(result.data.id);
    if (selectedType?.code === "desktop_pc") setIntakeMetadata((current) => ({ ...current, inventoryStatus: (device.attributes.inventory_status || "NOT_PERFORMED") as IntakeMetadata["inventoryStatus"] }));
    toast({ variant: "success", title: result.message });
    setStep(2);
  }
  // --------------------------------------------------------------------------
  // PASO 3 · RECEPCIÓN — VALIDACIONES ANTES DE LA CONFIRMACIÓN
  // Exige una descripción mínima del problema y completar todos los estados
  // de la inspección física antes de permitir avanzar al paso 4.
  // --------------------------------------------------------------------------
  function prepareConfirmation() {
    const next = validateReception(reportedProblem);
    setErrors(next);
    if (!Object.values(next).some(Boolean)) setStep(3);
  }
  // PASO 2 · DISPOSITIVO — ALTA RÁPIDA DE CATÁLOGOS
  // Permite registrar un tipo de dispositivo o una marca sin salir del flujo.
  async function createCatalog(name: string) {
    if (name.trim().length < 2) {
      setModalError("El nombre debe tener al menos 2 caracteres.");
      return;
    }
    setBusy(true);
    setModalError(undefined);
    const result =
      modal === "type"
        ? await createCustomDeviceTypeAction({ name })
        : modal === "brand"
          ? await createCustomBrandAction({ name, typeId: device.typeId })
          : modal === "model"
            ? await createCustomDeviceModelAction({
                name,
                typeId: device.typeId,
                brandId: device.brandId,
              })
            : await createCustomDeviceColorAction({ name });
    setBusy(false);
    if (!result.ok) {
      setModalError(result.message);
      toast({ variant: "error", title: result.message });
      return;
    }
    if (modal === "type") {
      setTypes((current) => [...current, result.data]);
      chooseType(result.data.id);
    } else if (modal === "brand") {
      setBrands((current) => [...current, result.data]);
      setDevice((current) => ({
        ...current,
        brandId: result.data.id,
        modelId: "",
        model: "",
      }));
    } else if (modal === "model") {
      const model = result.data as DeviceModelOption;
      setModels((current) => [...current, model]);
      setDevice((current) => ({
        ...current,
        modelId: model.id,
        model: model.name,
      }));
    } else {
      const color = result.data as DeviceColorOption;
      setColors((current) => [...current, color]);
      setDevice((current) => ({
        ...current,
        color: color.id,
        customColor: "",
      }));
    }
    toast({ variant: "success", title: result.message });
    setModal(null);
  }

  async function createDynamicCatalog(name: string) {
    if (!dynamicModal) return;
    setBusy(true);
    setModalError(undefined);
    const result = await createDynamicCatalogOptionAction({
      sourceKey: dynamicModal.sourceKey,
      parentId: dynamicModal.parentId,
      grandparentId: dynamicModal.grandparentId,
      name,
    });
    setBusy(false);
    if (!result.ok) {
      setModalError(result.message);
      toast({ variant: "error", title: result.message });
      return;
    }
    if (dynamicModal.accessory) {
      setAccessories((current) => [
        ...current.filter((item) => item.id !== result.data.id),
        result.data,
      ]);
      setDevice((current) => ({
        ...current,
        accessories: [...new Set([...current.accessories, result.data.id])],
      }));
    } else {
      setFieldCatalogs((current) => ({
        ...current,
        [dynamicModal.sourceKey]: [
          ...(current[dynamicModal.sourceKey] ?? []).filter(
            (item) => item.id !== result.data.id,
          ),
          result.data,
        ],
      }));
      if (dynamicModal.fieldKey)
        setDevice((current) => ({
          ...current,
          attributes: {
            ...current.attributes,
            [dynamicModal.fieldKey!]: result.data.id,
          },
        }));
      if (dynamicModal.storageIndex !== undefined)
        setDevice((current) => ({
          ...current,
          storageUnits: current.storageUnits.map((unit, index) =>
            index === dynamicModal.storageIndex
              ? { ...unit, type: result.data.id }
              : unit,
          ),
        }));
    }
    toast({ variant: "success", title: result.message });
    setDynamicModal(null);
  }
  // --------------------------------------------------------------------------
  // PASO 4 · CONFIRMACIÓN — VALIDACIÓN FINAL Y REGISTRO DE RECEPCIÓN
  // Requiere aceptación explícita, congela el snapshot y luego sube las fotos.
  // --------------------------------------------------------------------------
  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!termsAccepted) {
      setFieldError(
        "termsAccepted",
        "Confirmá que la información fue revisada con el cliente.",
      );
      return;
    }
    setBusy(true);
    const result = await confirmReceptionAction({
      customerId,
      deviceId,
      reportedProblem,
      observations,
      inspection: inspection.filter((item) => item.status).map((item) => ({
        key: item.key,
        label: item.label,
        status: item.status,
        observation: item.observation,
      })),
      intakeMetadata,
    });
    if (!result.ok) {
      setBusy(false);
      toast({ variant: "error", title: result.message });
      return;
    }
    toast({ variant: "success", title: result.message });
    await uploadPhotos(result.data.id, result.data.photoPrefix);
    disposePhotos();
    setBusy(false);
    setCompleted(true);
  }

  // --------------------------------------------------------------------------
  // ESTADO FINAL · RECEPCIÓN COMPLETADA
  // --------------------------------------------------------------------------
  if (completed)
    return (
      <Card className="mx-auto max-w-2xl p-6 text-center sm:p-10">
        <span className="mx-auto grid size-16 place-items-center rounded-full bg-success-soft text-success">
          <Check className="size-8" />
        </span>
        <p className="mt-6 text-xs font-bold uppercase tracking-[0.18em] text-success">
          Recepción registrada
        </p>
        <h2 className="mt-2 text-2xl font-bold text-primary">
          El ingreso del equipo quedó documentado
        </h2>
        <p className="mx-auto mt-3 max-w-lg text-sm leading-6 text-muted">
          Guardamos el cliente, el dispositivo y el snapshot inmutable de
          recepción de {customerName}.
        </p>
        <Link
          className="mt-7 inline-flex min-h-11 items-center justify-center rounded-lg bg-accent-button px-5 text-sm font-bold text-white hover:bg-accent-button-hover"
          href="/repairs"
        >
          Volver a reparaciones
        </Link>
      </Card>
    );

  // ============================================================================
  // RENDER PRINCIPAL DEL WIZARD DE RECEPCIÓN
  // ============================================================================
  return (
    <>
      <form className="mx-auto w-full max-w-6xl" onSubmit={handleSubmit}>
        <Card className="overflow-visible">
          <div className="overflow-hidden rounded-t-xl">
            <ol
              aria-label="Progreso de recepción"
              className="grid grid-cols-4 border-b border-border bg-surface-soft"
            >
              {WIZARD_STEPS.map((label, index) => (
                <li
                  aria-current={index === step ? "step" : undefined}
                  className={cn(
                    "px-2 py-4 text-center",
                    index < step && "text-success",
                    index === step
                      ? "bg-surface-raised text-accent"
                      : "text-muted",
                  )}
                  key={label}
                >
                  <span
                    className={cn(
                      "mx-auto grid size-7 place-items-center rounded-full border text-xs font-bold",
                      index < step
                        ? "border-success bg-success text-white"
                        : index === step
                          ? "border-accent bg-accent-soft"
                          : "border-border bg-surface",
                    )}
                  >
                    {index < step ? <Check className="size-4" /> : index + 1}
                  </span>

                  <span className="mt-2 block text-[11px] font-bold sm:text-xs">
                    {label}
                  </span>
                </li>
              ))}
            </ol>
          </div>

          <div className="p-5 sm:p-7 lg:p-8">
            {/* ============================================================
                PASO 1 · IDENTIFICACIÓN DEL CLIENTE
                ============================================================ */}
            {step === 0 && (
              <CustomerStep
                customers={customers}
                customerId={customerId}
                customer={customer}
                errors={errors}
                chooseCustomer={chooseCustomer}
                update={updateCustomer}
                touch={(key) =>
                  setTouched((current) => new Set(current).add(key))
                }
              />
            )}
            {/* ============================================================
                PASO 2 · DATOS DEL DISPOSITIVO
                ============================================================ */}
            {step === 1 && (
              <DeviceStep
                types={types}
                brands={brands}
                models={models}
                variants={variants}
                device={device}
                errors={errors}
                setDevice={setDevice}
                chooseType={chooseType}
                chooseBrand={chooseBrand}
                chooseModel={chooseModel}
                brandCatalogState={brandCatalogState}
                modelCatalogState={modelCatalogState}
                variantCatalogState={variantCatalogState}
                sections={initialData.formSectionsByType[device.typeId] ?? []}
                fieldCatalogs={fieldCatalogs}
                setDynamicAttribute={(key, value) => chooseTechnicalField(key, value, selectedType?.code, device.attributes)}
                processorCatalogStates={processorCatalogStates}
                processorCatalogErrors={processorCatalogErrors}
                deviceTypeName={selectedType?.name ?? "el tipo seleccionado"}
                deviceTypeCode={selectedType?.code}
              />
            )}
            {/* ============================================================
                PASO 3 · RECEPCIÓN E INSPECCIÓN DEL EQUIPO
                ============================================================ */}
            {step === 2 && (
              <IntakeStep
                inspection={inspection}
                setInspection={setInspection}
                condition={condition}
                reportedProblem={reportedProblem}
                setReportedProblem={setReportedProblem}
                observations={observations}
                setObservations={setObservations}
                intakeMetadata={intakeMetadata}
                setIntakeMetadata={setIntakeMetadata}
                photos={photos}
                setPhotos={setPhotos}
                addPhotos={addPhotos}
                errors={errors}
                deviceTypeCode={selectedType?.code}
                accessories={accessories}
              />
            )}
            {/* ============================================================
                PASO 4 · CONFIRMACIÓN FINAL
                ============================================================ */}
            {step === 3 && (
              <ConfirmationStep
                customerName={customerName}
                customer={selectedCustomer ?? customer}
                typeName={selectedType?.name ?? ""}
                brandName={selectedBrand?.name ?? ""}
                device={device}
                condition={condition}
                reportedProblem={reportedProblem}
                accessoryNames={device.accessories
                  .map((id) => accessories.find((item) => item.id === id)?.name)
                  .filter((name): name is string => Boolean(name))}
                termsAccepted={termsAccepted}
                setTermsAccepted={setTermsAccepted}
                error={errors.termsAccepted}
              />
            )}
            <div className="mt-8 flex flex-col-reverse gap-3 border-t border-border pt-5 sm:flex-row sm:items-center sm:justify-between">
              <Button
                disabled={step === 0 || busy}
                onClick={() => {
                  setErrors({});
                  setStep((current) => Math.max(0, current - 1));
                }}
                variant="secondary"
              >
                <ChevronLeft className="size-4" />
                Anterior
              </Button>
              {step === 0 ? (
                <Button
                  loading={busy}
                  loadingText="Registrando cliente…"
                  onClick={completeCustomerStep}
                >
                  Continuar
                  <ChevronRight className="size-4" />
                </Button>
              ) : step === 1 ? (
                <Button
                  loading={busy}
                  loadingText="Guardando dispositivo…"
                  onClick={completeDeviceStep}
                >
                  Guardar y continuar
                  <ChevronRight className="size-4" />
                </Button>
              ) : step === 2 ? (
                <Button onClick={prepareConfirmation}>
                  Continuar
                  <ChevronRight className="size-4" />
                </Button>
              ) : (
                <Button
                  loading={busy}
                  loadingText="Registrando recepción…"
                  type="submit"
                >
                  <ClipboardCheck className="size-4" />
                  Confirmar recepción
                </Button>
              )}
            </div>
          </div>
        </Card>
      </form>
      <CatalogModal
        busy={busy}
        error={modalError}
        label={
          modal === "type"
            ? "Nombre del tipo"
            : modal === "brand"
              ? "Nombre de la marca"
              : modal === "model"
                ? "Nombre del modelo"
                : "Nombre del color"
        }
        onClose={() => {
          setModal(null);
          setModalError(undefined);
        }}
        onSubmit={createCatalog}
        open={modal !== null}
        title={
          modal === "type"
            ? "Registrar nuevo tipo"
            : modal === "brand"
              ? "Registrar nueva marca"
              : modal === "model"
                ? "Registrar nuevo modelo"
                : "Registrar nuevo color"
        }
      />
      <CatalogModal
        busy={busy}
        error={modalError}
        label="Nombre"
        onClose={() => {
          setDynamicModal(null);
          setModalError(undefined);
        }}
        onSubmit={createDynamicCatalog}
        open={dynamicModal !== null}
        title={
          dynamicModal?.sourceKey.endsWith("_brand")
            ? "Registrar nueva marca"
            : dynamicModal?.accessory
              ? "Registrar nuevo accesorio"
              : dynamicModal?.sourceKey === "storage_type"
                ? "Registrar tipo de almacenamiento"
                : "Registrar nuevo modelo"
        }
      />
    </>
  );
}
