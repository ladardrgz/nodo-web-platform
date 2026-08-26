"use client";

import { ChevronDown, LoaderCircle, MapPin, Navigation, Route } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useRef, useState, type FormEvent } from "react";

import { useToast } from "@/components/feedback/ToastProvider";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { normalizeAddressText, organizationStepThreeSchema } from "@/features/organizations/schemas";
import { selectCountry, selectLocality, selectProvince } from "@/features/organizations/location-state";
import {
  initialOrganizationStepThreeState,
  loadLocalitiesAction,
  loadNeighborhoodsAction,
  loadProvincesAction,
  saveOrganizationStepThreeAction,
  type OrganizationStepThreeActionState,
} from "@/features/organizations/step-three-actions";
import { cn } from "@/lib/cn";
import type { GeographyOption, InitialSetupLocationData } from "@/types/geography";

type FieldName = "countryId" | "provinceId" | "localityId" | "neighborhoodId" | "street" | "streetNumber" | "floor" | "apartment" | "postalCode" | "reference";
type FieldErrors = Partial<Record<FieldName, string>>;
type LocationValues = Record<FieldName, string> & { withoutNumber: boolean };

function validationErrors(values: LocationValues, neighborhoodRequired: boolean): FieldErrors {
  const result = organizationStepThreeSchema.safeParse(values);
  const errors: FieldErrors = {};
  if (!result.success) {
    const fields = result.error.flatten().fieldErrors;
    for (const field of Object.keys(fields) as FieldName[]) errors[field] = fields[field]?.[0];
  }
  if (neighborhoodRequired && !values.neighborhoodId) errors.neighborhoodId = "Seleccione un barrio.";
  return errors;
}

function describedBy(...ids: Array<string | false | undefined>): string | undefined {
  return ids.filter(Boolean).join(" ") || undefined;
}

function SelectControl({
  disabled,
  error,
  id,
  loading,
  name,
  onBlur,
  onChange,
  options,
  placeholder,
  value,
}: {
  disabled?: boolean;
  error?: string;
  id: FieldName;
  loading?: boolean;
  name: string;
  onBlur: () => void;
  onChange: (value: string) => void;
  options: GeographyOption[];
  placeholder: string;
  value: string;
}) {
  return (
    <div className="input-with-trailing-icon relative">
      <select
        aria-describedby={error ? `${id}-error` : undefined}
        aria-invalid={Boolean(error)}
        className={cn("field-control appearance-none", error && "field-control-invalid")}
        disabled={disabled || loading}
        id={id}
        name={name}
        onBlur={onBlur}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        <option value="">{loading ? "Cargando..." : placeholder}</option>
        {options.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
      </select>
      {loading
        ? <LoaderCircle aria-hidden="true" className="input-trailing-icon animate-spin" />
        : <ChevronDown aria-hidden="true" className="input-trailing-icon" />}
    </div>
  );
}

interface OrganizationStepThreeFormProps {
  completedInitially: boolean;
  locationData: InitialSetupLocationData;
  onBack: () => void;
  onSaved: () => void;
}

export function OrganizationStepThreeForm({ completedInitially, locationData, onBack, onSaved }: OrganizationStepThreeFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const address = locationData.address;
  const [values, setValues] = useState<LocationValues>({
    countryId: address?.country_id ?? locationData.defaultCountryId,
    provinceId: address?.province_id ?? "",
    localityId: address?.locality_id ?? "",
    neighborhoodId: address?.neighborhood_id ?? "",
    street: address?.street ?? "",
    streetNumber: address?.street_number ? String(address.street_number) : "",
    withoutNumber: address?.without_number ?? false,
    floor: address?.floor ?? "",
    apartment: address?.apartment ?? "",
    postalCode: address?.postal_code ?? "",
    reference: address?.reference ?? "",
  });
  const [provinces, setProvinces] = useState(locationData.provinces);
  const [localities, setLocalities] = useState(locationData.localities);
  const [neighborhoods, setNeighborhoods] = useState(locationData.neighborhoods);
  const [loadingProvinces, setLoadingProvinces] = useState(false);
  const [loadingLocalities, setLoadingLocalities] = useState(false);
  const [loadingNeighborhoods, setLoadingNeighborhoods] = useState(false);
  const provinceRequest = useRef(0);
  const localityRequest = useRef(0);
  const neighborhoodRequest = useRef(0);
  const [touched, setTouched] = useState<Set<FieldName>>(new Set());
  const [clientErrors, setClientErrors] = useState<FieldErrors>({});
  const [state, action] = useActionState(async (previous: OrganizationStepThreeActionState, formData: FormData) => {
    const next = await saveOrganizationStepThreeAction(previous, formData);
    if (next.feedback) toast(next.feedback);
    if (next.status === "success") {
      onSaved();
      router.refresh();
    }
    return { ...next, feedback: undefined };
  }, initialOrganizationStepThreeState);

  const fieldError = (field: FieldName) => Object.hasOwn(clientErrors, field)
    ? clientErrors[field]
    : state.fieldErrors?.[field]?.[0];

  const updateField = (field: FieldName, value: string) => {
    const next = { ...values, [field]: value };
    setValues(next);
    if (touched.has(field)) setClientErrors((current) => ({ ...current, [field]: validationErrors(next, neighborhoods.length > 0)[field] }));
  };

  const blurField = (field: FieldName) => {
    const normalized = field === "postalCode"
      ? values[field].trim().toUpperCase()
      : normalizeAddressText(values[field]);
    const next = { ...values, [field]: normalized };
    setValues(next);
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: validationErrors(next, neighborhoods.length > 0)[field] }));
  };

  const changeCountry = async (countryId: string) => {
    const request = ++provinceRequest.current;
    localityRequest.current += 1;
    neighborhoodRequest.current += 1;
    const next = selectCountry(values, countryId);
    setValues(next);
    setProvinces([]);
    setLocalities([]);
    setNeighborhoods([]);
    setLoadingProvinces(false);
    setLoadingLocalities(false);
    setLoadingNeighborhoods(false);
    if (!countryId) return;
    setLoadingProvinces(true);
    const result = await loadProvincesAction(countryId);
    if (request !== provinceRequest.current) return;
    setLoadingProvinces(false);
    setProvinces(result.options);
    if (result.error) toast({ variant: "error", title: result.error });
  };

  const changeProvince = async (provinceId: string) => {
    const request = ++localityRequest.current;
    neighborhoodRequest.current += 1;
    const next = selectProvince(values, provinceId);
    setValues(next);
    setLocalities([]);
    setNeighborhoods([]);
    setLoadingLocalities(false);
    setLoadingNeighborhoods(false);
    if (!provinceId) return;
    setLoadingLocalities(true);
    const result = await loadLocalitiesAction(provinceId);
    if (request !== localityRequest.current) return;
    setLoadingLocalities(false);
    setLocalities(result.options);
    if (result.error) toast({ variant: "error", title: result.error });
  };

  const changeLocality = async (localityId: string) => {
    const request = ++neighborhoodRequest.current;
    const next = selectLocality(values, localityId);
    setValues(next);
    setNeighborhoods([]);
    setLoadingNeighborhoods(false);
    if (!localityId) return;
    setLoadingNeighborhoods(true);
    const result = await loadNeighborhoodsAction(localityId);
    if (request !== neighborhoodRequest.current) return;
    setLoadingNeighborhoods(false);
    setNeighborhoods(result.options);
    if (result.error) toast({ variant: "error", title: result.error });
  };

  const toggleWithoutNumber = (checked: boolean) => {
    const next = { ...values, withoutNumber: checked, streetNumber: checked ? "" : values.streetNumber };
    setValues(next);
    if (touched.has("streetNumber")) setClientErrors((current) => ({ ...current, streetNumber: validationErrors(next, neighborhoods.length > 0).streetNumber }));
  };

  const validateSubmit = (event: FormEvent<HTMLFormElement>) => {
    const errors = validationErrors(values, neighborhoods.length > 0);
    if (Object.values(errors).some(Boolean)) {
      event.preventDefault();
      setTouched(new Set(Object.keys(values).filter((key) => key !== "withoutNumber") as FieldName[]));
      setClientErrors(errors);
      toast({ variant: "error", title: "Completá los campos obligatorios antes de continuar." });
      return;
    }
    setClientErrors({});
  };

  const localityPlaceholder = !values.provinceId
    ? "Primero seleccione una provincia"
    : localities.length === 0 && !loadingLocalities
      ? "No hay localidades disponibles"
      : "Seleccione una localidad";
  const neighborhoodPlaceholder = !values.localityId
    ? "Primero seleccione una localidad"
    : neighborhoods.length === 0 && !loadingNeighborhoods
      ? "No hay barrios disponibles para esta localidad"
      : "Seleccione un barrio";

  return (
    <form action={action} className="space-y-6" noValidate onSubmit={validateSubmit}>
      <div className="flex items-start gap-3 rounded-xl border border-line bg-surface-soft p-4">
        <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-surface text-accent ring-1 ring-inset ring-line"><Navigation aria-hidden="true" className="size-4" /></span>
        <div><h3 className="font-semibold text-ink">Domicilio principal</h3><p className="mt-1 text-sm leading-6 text-ink-muted">La ubicación queda estructurada para utilizarla posteriormente en comprobantes y servicios basados en localidad.</p></div>
      </div>

      <div className="grid gap-5 md:grid-cols-2">
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="countryId">País <span className="text-danger">*</span></label>
          <SelectControl error={fieldError("countryId")} id="countryId" name="countryId" onBlur={() => blurField("countryId")} onChange={changeCountry} options={locationData.countries} placeholder="Seleccione un país" value={values.countryId} />
          {fieldError("countryId") ? <p className="text-sm font-medium text-danger" id="countryId-error">{fieldError("countryId")}</p> : null}
        </div>
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="provinceId">Provincia <span className="text-danger">*</span></label>
          <SelectControl disabled={!values.countryId} error={fieldError("provinceId")} id="provinceId" loading={loadingProvinces} name="provinceId" onBlur={() => blurField("provinceId")} onChange={changeProvince} options={provinces} placeholder="Seleccione una provincia" value={values.provinceId} />
          {fieldError("provinceId") ? <p className="text-sm font-medium text-danger" id="provinceId-error">{fieldError("provinceId")}</p> : null}
        </div>
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="localityId">Localidad / Ciudad <span className="text-danger">*</span></label>
          <SelectControl disabled={!values.provinceId || (!loadingLocalities && localities.length === 0)} error={fieldError("localityId")} id="localityId" loading={loadingLocalities} name="localityId" onBlur={() => blurField("localityId")} onChange={changeLocality} options={localities} placeholder={localityPlaceholder} value={values.localityId} />
          {values.provinceId && !loadingLocalities && localities.length === 0 ? <p className="text-xs text-warning">No hay localidades disponibles para esta provincia.</p> : null}
          {fieldError("localityId") ? <p className="text-sm font-medium text-danger" id="localityId-error">{fieldError("localityId")}</p> : null}
        </div>
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="neighborhoodId">Barrio {neighborhoods.length > 0 ? <span className="text-danger">*</span> : <span className="text-xs font-normal text-ink-muted">(sin catálogo disponible)</span>}</label>
          <SelectControl disabled={!values.localityId || (!loadingNeighborhoods && neighborhoods.length === 0)} error={fieldError("neighborhoodId")} id="neighborhoodId" loading={loadingNeighborhoods} name="neighborhoodId" onBlur={() => blurField("neighborhoodId")} onChange={(value) => updateField("neighborhoodId", value)} options={neighborhoods} placeholder={neighborhoodPlaceholder} value={values.neighborhoodId} />
          {values.localityId && !loadingNeighborhoods && neighborhoods.length === 0 ? <p className="text-xs text-ink-muted">No hay barrios disponibles para esta localidad. Podés continuar sin seleccionar uno.</p> : null}
          {fieldError("neighborhoodId") ? <p className="text-sm font-medium text-danger" id="neighborhoodId-error">{fieldError("neighborhoodId")}</p> : null}
        </div>
      </div>

      <div className="grid gap-5 md:grid-cols-[minmax(0,1fr)_180px]">
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="street">Calle <span className="text-danger">*</span></label>
          <div className="input-with-leading-icon relative"><Route aria-hidden="true" className="input-leading-icon" /><input aria-describedby={describedBy(fieldError("street") && "street-error")} aria-invalid={Boolean(fieldError("street"))} className={cn("field-control", fieldError("street") && "field-control-invalid")} id="street" maxLength={120} name="street" onBlur={() => blurField("street")} onChange={(event) => updateField("street", event.target.value)} placeholder="Ingrese la calle" value={values.street} /></div>
          {fieldError("street") ? <p className="text-sm font-medium text-danger" id="street-error">{fieldError("street")}</p> : null}
        </div>
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="streetNumber">Altura <span className="text-danger">*</span></label>
          <input aria-describedby={describedBy(fieldError("streetNumber") && "streetNumber-error")} aria-invalid={Boolean(fieldError("streetNumber"))} className={cn("field-control", fieldError("streetNumber") && "field-control-invalid")} disabled={values.withoutNumber} id="streetNumber" inputMode="numeric" maxLength={6} name="streetNumber" onBlur={() => blurField("streetNumber")} onChange={(event) => updateField("streetNumber", event.target.value.replace(/\D/g, ""))} placeholder="Ej. 1250" value={values.streetNumber} />
          <input name="withoutNumber" type="hidden" value={String(values.withoutNumber)} />
          <label className="flex min-h-9 cursor-pointer items-center gap-2 text-sm text-ink-secondary"><input checked={values.withoutNumber} className="size-4 accent-[var(--accent)]" onChange={(event) => toggleWithoutNumber(event.target.checked)} type="checkbox" />Sin número</label>
          {fieldError("streetNumber") ? <p className="text-sm font-medium text-danger" id="streetNumber-error">{fieldError("streetNumber")}</p> : null}
        </div>
      </div>

      <div className="grid gap-5 sm:grid-cols-3">
        {([
          ["floor", "Piso", "Ej. PB"],
          ["apartment", "Departamento", "Ej. 2C"],
          ["postalCode", "Código postal", "Ej. P3600ABC"],
        ] as const).map(([field, label, placeholder]) => (
          <div className="space-y-2" key={field}>
            <label className="block text-sm font-semibold text-ink" htmlFor={field}>{label} <span className="text-xs font-normal text-ink-muted">(opcional)</span></label>
            <input aria-describedby={fieldError(field) ? `${field}-error` : undefined} aria-invalid={Boolean(fieldError(field))} className={cn("field-control", fieldError(field) && "field-control-invalid")} id={field} maxLength={field === "postalCode" ? 10 : 10} name={field} onBlur={() => blurField(field)} onChange={(event) => updateField(field, event.target.value)} placeholder={placeholder} value={values[field]} />
            {fieldError(field) ? <p className="text-sm font-medium text-danger" id={`${field}-error`}>{fieldError(field)}</p> : null}
          </div>
        ))}
      </div>

      <div className="space-y-2">
        <label className="block text-sm font-semibold text-ink" htmlFor="reference">Referencia <span className="text-xs font-normal text-ink-muted">(opcional)</span></label>
        <div className="relative"><MapPin aria-hidden="true" className="pointer-events-none absolute left-3 top-3 size-5 text-ink-muted" /><textarea aria-describedby={describedBy("reference-help", fieldError("reference") && "reference-error")} aria-invalid={Boolean(fieldError("reference"))} className={cn("field-control min-h-24 resize-y pl-12", fieldError("reference") && "field-control-invalid")} id="reference" maxLength={200} name="reference" onBlur={() => blurField("reference")} onChange={(event) => updateField("reference", event.target.value)} placeholder="Ej. Local con portón gris" value={values.reference} /></div>
        <p className="text-xs text-ink-muted" id="reference-help">Máximo 200 caracteres. No incluyas información sensible.</p>
        {fieldError("reference") ? <p className="text-sm font-medium text-danger" id="reference-error">{fieldError("reference")}</p> : null}
      </div>

      <div className="flex flex-col-reverse gap-3 border-t border-line pt-5 sm:flex-row sm:items-center sm:justify-between">
        <Button className="w-full sm:w-auto" onClick={onBack} variant="secondary">Volver</Button>
        <SubmitButton className="w-full sm:w-auto" label={completedInitially ? "Guardar cambios y continuar" : "Guardar y continuar"} pendingLabel="Guardando..." />
      </div>
    </form>
  );
}
