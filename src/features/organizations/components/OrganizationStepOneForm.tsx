"use client";

import { Building2, ImagePlus, Store, Upload, X } from "lucide-react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useRef, useState, type FormEvent } from "react";

import { useToast } from "@/components/feedback/ToastProvider";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import {
  ORGANIZATION_LOGO_MAX_BYTES,
  normalizeOrganizationText,
  organizationStepOneSchema,
  validateOrganizationLogo,
} from "@/features/organizations/schemas";
import {
  initialOrganizationStepOneState,
  saveOrganizationStepOneAction,
  type OrganizationStepOneActionState,
} from "@/features/organizations/step-one-actions";
import { cn } from "@/lib/cn";
import type { OwnerOrganization } from "@/types/organization";

type FieldName = "legalName" | "commercialName";
type FieldErrors = Partial<Record<FieldName | "logo", string>>;

function validationErrors(values: Record<FieldName, string>): FieldErrors {
  const result = organizationStepOneSchema.safeParse(values);
  if (result.success) return {};
  const fields = result.error.flatten().fieldErrors;
  return {
    legalName: fields.legalName?.[0],
    commercialName: fields.commercialName?.[0],
  };
}

function describedBy(...ids: Array<string | false | undefined>): string | undefined {
  const value = ids.filter(Boolean).join(" ");
  return value || undefined;
}

interface OrganizationStepOneFormProps {
  completedInitially: boolean;
  logoUrl: string | null;
  onSaved: () => void;
  organization: OwnerOrganization;
}

export function OrganizationStepOneForm({ completedInitially, logoUrl, onSaved, organization }: OrganizationStepOneFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const logoInputRef = useRef<HTMLInputElement>(null);
  const previewObjectUrlRef = useRef<string | null>(null);
  const [values, setValues] = useState({
    legalName: organization.name,
    commercialName: organization.trade_name ?? "",
  });
  const [touched, setTouched] = useState<Set<FieldName>>(new Set());
  const [clientErrors, setClientErrors] = useState<FieldErrors>({});
  const [selectedLogo, setSelectedLogo] = useState<File | null>(null);
  const [logoPreview, setLogoPreview] = useState<string | null>(logoUrl);
  const [state, action] = useActionState(async (previous: OrganizationStepOneActionState, formData: FormData) => {
    const next = await saveOrganizationStepOneAction(previous, formData);
    if (next.feedback) toast(next.feedback);
    if (next.status === "success") {
      onSaved();
      router.refresh();
    }
    return { ...next, feedback: undefined };
  }, initialOrganizationStepOneState);

  useEffect(() => () => {
    if (previewObjectUrlRef.current) URL.revokeObjectURL(previewObjectUrlRef.current);
  }, []);

  const fieldError = (field: FieldName) => (
    Object.hasOwn(clientErrors, field) ? clientErrors[field] : state.fieldErrors?.[field]?.[0]
  );
  const logoError = Object.hasOwn(clientErrors, "logo") ? clientErrors.logo : state.fieldErrors?.logo?.[0];

  const updateField = (field: FieldName, value: string) => {
    const nextValues = { ...values, [field]: value };
    setValues(nextValues);
    if (touched.has(field)) {
      setClientErrors((current) => ({ ...current, [field]: validationErrors(nextValues)[field] }));
    }
  };

  const blurField = (field: FieldName) => {
    const nextValues = { ...values, [field]: normalizeOrganizationText(values[field]) };
    setValues(nextValues);
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: validationErrors(nextValues)[field] }));
  };

  const selectLogo = (file: File | null) => {
    const error = validateOrganizationLogo(file);
    setClientErrors((current) => ({ ...current, logo: error ?? undefined }));
    if (error) {
      if (previewObjectUrlRef.current) URL.revokeObjectURL(previewObjectUrlRef.current);
      previewObjectUrlRef.current = null;
      setSelectedLogo(null);
      setLogoPreview(logoUrl);
      if (logoInputRef.current) logoInputRef.current.value = "";
      return;
    }
    if (previewObjectUrlRef.current) URL.revokeObjectURL(previewObjectUrlRef.current);
    previewObjectUrlRef.current = file ? URL.createObjectURL(file) : null;
    setSelectedLogo(file);
    setLogoPreview(previewObjectUrlRef.current ?? logoUrl);
  };

  const clearLogoSelection = () => {
    if (previewObjectUrlRef.current) URL.revokeObjectURL(previewObjectUrlRef.current);
    previewObjectUrlRef.current = null;
    setSelectedLogo(null);
    setLogoPreview(logoUrl);
    setClientErrors((current) => ({ ...current, logo: undefined }));
    if (logoInputRef.current) logoInputRef.current.value = "";
  };

  const validateSubmit = (event: FormEvent<HTMLFormElement>) => {
    const errors = validationErrors(values);
    if (Object.values(errors).some(Boolean) || clientErrors.logo) {
      event.preventDefault();
      setTouched(new Set(["legalName", "commercialName"]));
      setClientErrors((current) => ({ ...current, ...errors }));
      toast({ variant: "error", title: "Completá los campos obligatorios antes de continuar." });
      return;
    }
    setClientErrors({});
  };

  return (
    <form action={action} className="space-y-6" noValidate onSubmit={validateSubmit}>
      <div className="flex items-start justify-between gap-3 rounded-xl border border-line bg-surface-soft p-4">
        <div>
          <h3 className="font-semibold text-ink">Identidad de la organización</h3>
          <p className="mt-1 text-sm leading-6 text-ink-muted">Estos nombres cumplen funciones diferentes dentro de Nodo.</p>
        </div>
        <ContextHelp label="Ayuda sobre razón social y nombre comercial" title="¿Qué datos debo ingresar?">
          La razón social identifica legalmente al responsable del negocio, mientras que el nombre comercial es el nombre con el que tu taller se presenta a sus clientes.
        </ContextHelp>
      </div>

      <div className="grid gap-5 md:grid-cols-2">
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="legalName">Razón social <span className="text-danger">*</span></label>
          <div className="input-with-leading-icon relative">
            <Building2 aria-hidden="true" className="input-leading-icon" />
            <input
              aria-describedby={describedBy("legalName-example", fieldError("legalName") && "legalName-error")}
              aria-invalid={Boolean(fieldError("legalName"))}
              aria-required="true"
              className={cn("field-control", fieldError("legalName") && "field-control-invalid")}
              id="legalName"
              maxLength={120}
              name="legalName"
              onBlur={() => blurField("legalName")}
              onChange={(event) => updateField("legalName", event.target.value)}
              placeholder="Ingrese la razón social"
              value={values.legalName}
            />
          </div>
          <p className="text-xs text-ink-muted" id="legalName-example">Ejemplo: R&amp;R Asociados S.R.L.</p>
          {fieldError("legalName") ? <p className="text-sm font-medium text-danger" id="legalName-error">{fieldError("legalName")}</p> : null}
        </div>

        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="commercialName">Nombre comercial <span className="text-danger">*</span></label>
          <div className="input-with-leading-icon relative">
            <Store aria-hidden="true" className="input-leading-icon" />
            <input
              aria-describedby={describedBy("commercialName-example", fieldError("commercialName") && "commercialName-error")}
              aria-invalid={Boolean(fieldError("commercialName"))}
              aria-required="true"
              className={cn("field-control", fieldError("commercialName") && "field-control-invalid")}
              id="commercialName"
              maxLength={120}
              name="commercialName"
              onBlur={() => blurField("commercialName")}
              onChange={(event) => updateField("commercialName", event.target.value)}
              placeholder="Ingrese el nombre comercial"
              value={values.commercialName}
            />
          </div>
          <p className="text-xs text-ink-muted" id="commercialName-example">Ejemplo: R&amp;R</p>
          {fieldError("commercialName") ? <p className="text-sm font-medium text-danger" id="commercialName-error">{fieldError("commercialName")}</p> : null}
        </div>
      </div>

      <div className="space-y-2">
        <div>
          <span className="block text-sm font-semibold text-ink">Logo de la organización</span>
          <p className="mt-1 text-xs text-ink-muted">Opcional · PNG, JPG o WebP · Máximo {ORGANIZATION_LOGO_MAX_BYTES / 1024 / 1024} MB</p>
        </div>
        <div className={cn("grid gap-4 rounded-xl border border-dashed bg-surface-soft p-4 sm:grid-cols-[120px_minmax(0,1fr)] sm:items-center", logoError ? "border-danger" : "border-line-strong")}>
          <div className="relative grid aspect-square w-full max-w-[120px] place-items-center overflow-hidden rounded-xl border border-line bg-surface">
            {logoPreview ? (
              <Image alt={`Vista previa del logo de ${values.commercialName || values.legalName || "la organización"}`} className="object-contain p-2" fill sizes="120px" src={logoPreview} unoptimized />
            ) : (
              <ImagePlus aria-hidden="true" className="size-8 text-ink-muted" />
            )}
          </div>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-ink">{selectedLogo ? selectedLogo.name : logoUrl ? "Logo actual" : "Todavía no seleccionaste un logo"}</p>
            <p className="mt-1 text-xs leading-5 text-ink-muted">La imagen conservará su proporción y no será deformada.</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <label className="inline-flex min-h-10 cursor-pointer items-center justify-center gap-2 rounded-lg bg-surface px-3 text-sm font-semibold text-ink ring-1 ring-inset ring-line transition hover:bg-surface-soft focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-accent">
                <Upload className="size-4" />
                {selectedLogo || logoUrl ? "Reemplazar archivo" : "Seleccionar archivo"}
                <input
                  accept="image/png,image/jpeg,image/webp"
                  className="sr-only"
                  id="logo"
                  name="logo"
                  onChange={(event) => selectLogo(event.target.files?.[0] ?? null)}
                  ref={logoInputRef}
                  type="file"
                />
              </label>
              {selectedLogo ? (
                <Button onClick={clearLogoSelection} size="sm" variant="ghost">
                  <X className="size-4" />
                  Quitar selección
                </Button>
              ) : null}
            </div>
            {logoError ? <p className="mt-2 text-sm font-medium text-danger" id="logo-error">{logoError}</p> : null}
          </div>
        </div>
      </div>

      <div className="flex justify-end border-t border-line pt-5">
        <SubmitButton
          className="w-full sm:w-auto"
          label={completedInitially ? "Guardar cambios y continuar" : "Guardar y continuar"}
          pendingLabel="Guardando..."
        />
      </div>
    </form>
  );
}
