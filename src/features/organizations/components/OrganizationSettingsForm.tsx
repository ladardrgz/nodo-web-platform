"use client";

import { Building2, ImageUp, Mail, MapPin, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { parsePhoneNumber, type Country } from "react-phone-number-input";

import { useToast } from "@/components/feedback/ToastProvider";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { initialOrganizationSetupState, type OrganizationSetupActionState } from "@/features/organizations/action-states";
import { saveOrganizationSetupAction } from "@/features/organizations/actions";
import { GeographySelect } from "@/features/organizations/components/GeographySelect";
import { InternationalPhoneField } from "@/features/organizations/components/InternationalPhoneField";
import { normalizeInternationalPhone, organizationSettingsInputSchema } from "@/features/organizations/organization-settings-schema";
import { loadLocalitiesAction, loadNeighborhoodsAction, loadProvincesAction } from "@/features/organizations/step-three-actions";
import { cn } from "@/lib/cn";
import { ORGANIZATION_LOGO_MAX_BYTES, validateOrganizationLogoMetadata } from "@/lib/organizations/logo-validation";
import type { InitialSetupLocationData } from "@/types/geography";
import type { OwnerOrganization } from "@/types/organization";

type FieldName = "name" | "phoneCountry" | "phoneNationalNumber" | "contactEmail" | "countryId" | "provinceId" | "localityId" | "neighborhoodId" | "addressLine" | "logo";
type FieldErrors = Partial<Record<FieldName, string | undefined>>;
type SettingsValues = {
  name: string;
  phoneCountry: Country;
  phoneNationalNumber: string;
  contactEmail: string;
  countryId: string;
  provinceId: string;
  localityId: string;
  neighborhoodId: string;
  addressLine: string;
};

function getInitialPhone(organization: OwnerOrganization): Pick<SettingsValues, "phoneCountry" | "phoneNationalNumber"> {
  if (organization.phone_country_code && organization.phone_national_number) {
    return { phoneCountry: organization.phone_country_code as Country, phoneNationalNumber: organization.phone_national_number };
  }
  try {
    const parsed = organization.phone ? parsePhoneNumber(organization.phone) : undefined;
    if (parsed?.country) return { phoneCountry: parsed.country, phoneNationalNumber: parsed.nationalNumber };
  } catch {
    // Un teléfono legacy inválido se muestra vacío para exigir una corrección explícita.
  }
  return { phoneCountry: "AR", phoneNationalNumber: "" };
}

function validate(values: SettingsValues, neighborhoodRequired: boolean): FieldErrors {
  const parsed = organizationSettingsInputSchema.safeParse(values);
  const errors: FieldErrors = {};
  if (!parsed.success) {
    const fields = parsed.error.flatten().fieldErrors as Partial<Record<Exclude<FieldName, "logo">, string[]>>;
    for (const field of Object.keys(fields) as Array<Exclude<FieldName, "logo">>) errors[field] = fields[field]?.[0];
  }
  if (neighborhoodRequired && !values.neighborhoodId) errors.neighborhoodId = "Seleccioná un barrio.";
  return errors;
}

interface OrganizationSettingsFormProps {
  locationData: InitialSetupLocationData;
  logoUrl: string | null;
  organization: OwnerOrganization;
  personalEmail: string | null;
  personalPhone: string | null;
}

export function OrganizationSettingsForm({ locationData, logoUrl, organization, personalEmail, personalPhone }: OrganizationSettingsFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const initialPhone = getInitialPhone(organization);
  const address = locationData.address;
  const [values, setValues] = useState<SettingsValues>({
    name: organization.name,
    ...initialPhone,
    contactEmail: organization.contact_email ?? "",
    countryId: address?.country_id ?? locationData.defaultCountryId,
    provinceId: address?.province_id ?? "",
    localityId: address?.locality_id ?? "",
    neighborhoodId: address?.neighborhood_id ?? "",
    addressLine: address ? `${address.street} ${address.without_number ? "S/N" : address.street_number ?? ""}`.trim() : organization.address ?? "",
  });
  const [provinces, setProvinces] = useState(locationData.provinces);
  const [localities, setLocalities] = useState(locationData.localities);
  const [neighborhoods, setNeighborhoods] = useState(locationData.neighborhoods);
  const [loading, setLoading] = useState<"country" | "province" | "locality" | null>(null);
  const requestId = useRef(0);
  const [touched, setTouched] = useState<Set<FieldName>>(new Set());
  const [clientErrors, setClientErrors] = useState<FieldErrors>({});
  const [phoneDecision, setPhoneDecision] = useState<"yes" | "no" | null>(null);
  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [logoPreview, setLogoPreview] = useState(logoUrl);
  const [logoError, setLogoError] = useState<string>();
  const logoInput = useRef<HTMLInputElement>(null);
  const [confirmationOpen, setConfirmationOpen] = useState(false);
  const confirmationInput = useRef<HTMLInputElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);
  const formRef = useRef<HTMLFormElement>(null);

  const [state, action] = useActionState(async (previous: OrganizationSetupActionState, formData: FormData) => {
    const next = await saveOrganizationSetupAction(previous, formData);
    if (next.feedback) toast(next.feedback);
    setConfirmationOpen(false);
    if (next.status === "success") {
      setLogoFile(null);
      router.refresh();
    }
    return { ...next, feedback: undefined };
  }, initialOrganizationSetupState);

  useEffect(() => {
    if (!confirmationOpen) return;
    closeButton.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setConfirmationOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [confirmationOpen]);

  useEffect(() => () => {
    if (logoPreview?.startsWith("blob:")) URL.revokeObjectURL(logoPreview);
  }, [logoPreview]);

  const normalizedBusinessPhone = useMemo(
    () => normalizeInternationalPhone(values.phoneCountry, values.phoneNationalNumber)?.number ?? null,
    [values.phoneCountry, values.phoneNationalNumber],
  );
  const usesPersonalPhone = Boolean(personalPhone && normalizedBusinessPhone === personalPhone);
  const usesPersonalEmail = Boolean(personalEmail && values.contactEmail.trim().toLowerCase() === personalEmail.toLowerCase());

  const fieldError = (field: FieldName) => {
    if (field === "logo") return logoError ?? state.fieldErrors?.logo?.[0];
    return Object.hasOwn(clientErrors, field) ? clientErrors[field] : state.fieldErrors?.[field]?.[0];
  };

  const setField = <K extends keyof SettingsValues>(field: K, value: SettingsValues[K]) => {
    const next = { ...values, [field]: value };
    setValues(next);
    if (field === "phoneCountry" || field === "phoneNationalNumber") setPhoneDecision(null);
    if (touched.has(field as FieldName)) setClientErrors((current) => ({ ...current, [field]: validate(next, neighborhoods.length > 0)[field as FieldName] }));
    if (confirmationInput.current) confirmationInput.current.value = "false";
  };

  const setPhone = (country: Country, nationalNumber: string) => {
    const next = { ...values, phoneCountry: country, phoneNationalNumber: nationalNumber };
    setValues(next);
    setPhoneDecision(null);
    if (touched.has("phoneNationalNumber")) setClientErrors((current) => ({ ...current, phoneNationalNumber: validate(next, neighborhoods.length > 0).phoneNationalNumber }));
    if (confirmationInput.current) confirmationInput.current.value = "false";
  };

  const blur = (field: FieldName) => {
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: validate(values, neighborhoods.length > 0)[field] }));
  };

  const showLoadError = (message?: string) => {
    if (message) toast({ variant: "error", title: message });
  };

  const changeCountry = async (countryId: string) => {
    const currentRequest = ++requestId.current;
    setValues((current) => ({ ...current, countryId, provinceId: "", localityId: "", neighborhoodId: "" }));
    setProvinces([]); setLocalities([]); setNeighborhoods([]);
    if (!countryId) return;
    setLoading("country");
    const result = await loadProvincesAction(countryId);
    if (currentRequest !== requestId.current) return;
    setProvinces(result.options); setLoading(null); showLoadError(result.error);
  };

  const changeProvince = async (provinceId: string) => {
    const currentRequest = ++requestId.current;
    setValues((current) => ({ ...current, provinceId, localityId: "", neighborhoodId: "" }));
    setLocalities([]); setNeighborhoods([]);
    if (!provinceId) return;
    setLoading("province");
    const result = await loadLocalitiesAction(provinceId);
    if (currentRequest !== requestId.current) return;
    setLocalities(result.options); setLoading(null); showLoadError(result.error);
  };

  const changeLocality = async (localityId: string) => {
    const currentRequest = ++requestId.current;
    setValues((current) => ({ ...current, localityId, neighborhoodId: "" }));
    setNeighborhoods([]);
    if (!localityId) return;
    setLoading("locality");
    const result = await loadNeighborhoodsAction(localityId);
    if (currentRequest !== requestId.current) return;
    setNeighborhoods(result.options); setLoading(null); showLoadError(result.error);
  };

  const chooseLogo = (file: File | null) => {
    const error = validateOrganizationLogoMetadata(file);
    setLogoError(error ?? undefined);
    if (error || !file) {
      setLogoFile(null);
      if (logoInput.current) logoInput.current.value = "";
      return;
    }
    if (logoPreview?.startsWith("blob:")) URL.revokeObjectURL(logoPreview);
    setLogoFile(file);
    setLogoPreview(URL.createObjectURL(file));
  };

  const removeLogoSelection = () => {
    if (logoPreview?.startsWith("blob:")) URL.revokeObjectURL(logoPreview);
    setLogoFile(null); setLogoPreview(logoUrl); setLogoError(undefined);
    if (logoInput.current) logoInput.current.value = "";
  };

  const openConfirmation = () => {
    const errors = validate(values, neighborhoods.length > 0);
    if (logoError) errors.logo = logoError;
    if (Object.values(errors).some(Boolean)) {
      setTouched(new Set(Object.keys(values) as FieldName[]));
      setClientErrors(errors);
      return;
    }
    if (usesPersonalPhone && phoneDecision !== "yes") {
      setClientErrors((current) => ({ ...current, phoneNationalNumber: "Confirmá si querés utilizar tu número personal como contacto del negocio." }));
      return;
    }
    setClientErrors({});
    if (confirmationInput.current) confirmationInput.current.value = "false";
    setConfirmationOpen(true);
  };

  const confirmAndSubmit = () => {
    if (confirmationInput.current) confirmationInput.current.value = "true";
  };

  const interceptUnconfirmedSubmit = (event: FormEvent<HTMLFormElement>) => {
    if (confirmationInput.current?.value === "true") return;
    event.preventDefault();
    openConfirmation();
  };

  return (
    <form action={action} className="space-y-8" noValidate onSubmit={interceptUnconfirmedSubmit} ref={formRef}>
      <section className="space-y-5" aria-labelledby="identity-title">
        <div><h2 className="text-lg font-bold text-ink" id="identity-title">Organización</h2><p className="mt-1 text-sm text-ink-muted">Datos que identifican a tu negocio en Nodo y en sus comprobantes.</p></div>
        <FormField error={fieldError("name")} htmlFor="name" label="Nombre del negocio u organización" required>
          <div className="input-with-leading-icon relative"><Building2 aria-hidden="true" className="input-leading-icon" /><input aria-describedby="name-help" aria-invalid={Boolean(fieldError("name"))} className={cn("field-control", fieldError("name") && "field-control-invalid")} id="name" maxLength={120} name="name" onBlur={() => blur("name")} onChange={(event) => setField("name", event.target.value)} value={values.name} /></div>
          <p className="mt-2 text-xs text-ink-muted" id="name-help">Ingresá el nombre de tu local o negocio con el que prestás tus servicios.</p>
        </FormField>
      </section>

      <section className="space-y-5 border-t border-line pt-7" aria-labelledby="contact-title">
        <div><h2 className="text-lg font-bold text-ink" id="contact-title">Contacto del negocio</h2><p className="mt-1 text-sm text-ink-muted">Estos datos pueden coincidir con los personales del administrador.</p></div>
        <div className="grid gap-5 xl:grid-cols-2">
          <FormField error={fieldError("phoneNationalNumber")} htmlFor="phoneNationalNumber" label="Teléfono del negocio" required>
            <InternationalPhoneField country={values.phoneCountry} error={fieldError("phoneNationalNumber")} nationalNumber={values.phoneNationalNumber} onBlur={() => blur("phoneNationalNumber")} onChange={setPhone} />
            <p className="mt-2 text-xs text-ink-muted" id="phoneNationalNumber-help">Argentina (+54) está seleccionada por defecto. Ingresá únicamente el número nacional.</p>
            <input name="personalPhoneConfirmed" type="hidden" value={phoneDecision === "yes" ? "true" : "false"} />
            {(usesPersonalPhone || state.requiresPersonalPhoneConfirmation) ? <div className="mt-3 rounded-lg border border-warning/35 bg-warning-soft p-3 text-sm text-ink"><p>¿Confirmás utilizar tu número de teléfono personal como teléfono de contacto del negocio?</p><div className="mt-3 flex gap-2"><Button onClick={() => { setPhoneDecision("yes"); setClientErrors((current) => ({ ...current, phoneNationalNumber: undefined })); }} size="sm" variant={phoneDecision === "yes" ? "primary" : "secondary"}>Sí</Button><Button onClick={() => { setPhone(values.phoneCountry, ""); setPhoneDecision("no"); }} size="sm" variant="secondary">No</Button></div></div> : null}
          </FormField>

          <FormField error={fieldError("contactEmail")} htmlFor="contactEmail" label="Correo electrónico de contacto del negocio" required>
            <div className="input-with-leading-icon relative"><Mail aria-hidden="true" className="input-leading-icon" /><input aria-invalid={Boolean(fieldError("contactEmail"))} autoComplete="email" className={cn("field-control", fieldError("contactEmail") && "field-control-invalid")} id="contactEmail" maxLength={254} name="contactEmail" onBlur={() => blur("contactEmail")} onChange={(event) => setField("contactEmail", event.target.value)} placeholder="contacto@negocio.com" type="email" value={values.contactEmail} /></div>
            {usesPersonalEmail ? <p className="mt-2 text-xs text-warning">Podés utilizar tu correo personal, aunque recomendamos un correo propio del negocio para separar las comunicaciones.</p> : <p className="mt-2 text-xs text-ink-muted">Este correo no modifica tu email de acceso a Nodo.</p>}
          </FormField>
        </div>
      </section>

      <section className="space-y-5 border-t border-line pt-7" aria-labelledby="address-title">
        <div className="flex items-start gap-3"><span className="grid size-9 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><MapPin aria-hidden="true" className="size-4" /></span><div><h2 className="text-lg font-bold text-ink" id="address-title">Dirección</h2><p className="mt-1 text-sm text-ink-muted">La ubicación se guarda de forma estructurada para utilizarla correctamente en comprobantes.</p></div></div>
        <div className="grid gap-5 md:grid-cols-2">
          <FormField error={fieldError("countryId")} htmlFor="countryId" label="País" required><GeographySelect error={fieldError("countryId")} id="countryId" loading={loading === "country"} name="countryId" onBlur={() => blur("countryId")} onChange={changeCountry} options={locationData.countries} placeholder="Seleccione un país" value={values.countryId} /></FormField>
          <FormField error={fieldError("provinceId")} htmlFor="provinceId" label="Provincia / Estado" required><GeographySelect disabled={!values.countryId} error={fieldError("provinceId")} id="provinceId" loading={loading === "country"} name="provinceId" onBlur={() => blur("provinceId")} onChange={changeProvince} options={provinces} placeholder="Seleccione una provincia o estado" value={values.provinceId} /></FormField>
          <FormField error={fieldError("localityId")} htmlFor="localityId" label="Localidad / Ciudad" required><GeographySelect disabled={!values.provinceId} error={fieldError("localityId")} id="localityId" loading={loading === "province"} name="localityId" onBlur={() => blur("localityId")} onChange={changeLocality} options={localities} placeholder={values.provinceId ? "Seleccione una localidad o ciudad" : "Primero seleccione una provincia"} value={values.localityId} /></FormField>
          <FormField error={fieldError("neighborhoodId")} htmlFor="neighborhoodId" label={`Barrio${neighborhoods.length ? "" : " (opcional si no hay catálogo)"}`} required={neighborhoods.length > 0}><GeographySelect disabled={!values.localityId || neighborhoods.length === 0} error={fieldError("neighborhoodId")} id="neighborhoodId" loading={loading === "locality"} name="neighborhoodId" onBlur={() => blur("neighborhoodId")} onChange={(value) => setField("neighborhoodId", value)} options={neighborhoods} placeholder={neighborhoods.length ? "Seleccione un barrio" : "No hay barrios disponibles"} value={values.neighborhoodId} /></FormField>
          <div className="md:col-span-2"><FormField error={fieldError("addressLine")} htmlFor="addressLine" label="Calle y numeración" required><input aria-invalid={Boolean(fieldError("addressLine"))} autoComplete="street-address" className={cn("field-control", fieldError("addressLine") && "field-control-invalid")} id="addressLine" maxLength={140} name="addressLine" onBlur={() => blur("addressLine")} onChange={(event) => setField("addressLine", event.target.value)} placeholder="Ej. Av. 25 de Mayo 1250" value={values.addressLine} /><p className="mt-2 text-xs text-ink-muted">Para una dirección sin altura, terminá el campo con “S/N”.</p></FormField></div>
        </div>
      </section>

      <section className="space-y-5 border-t border-line pt-7" aria-labelledby="logo-title">
        <div><h2 className="text-lg font-bold text-ink" id="logo-title">Logo</h2><p className="mt-1 text-sm text-ink-muted">Identidad visual opcional del negocio.</p></div>
        <FormField error={fieldError("logo")} htmlFor="logo" label="Logo de la organización" hint={`JPG, PNG, WebP o AVIF. Máximo ${ORGANIZATION_LOGO_MAX_BYTES / 1024 / 1024} MB.`}>
          <div className="flex flex-col gap-4 rounded-xl border border-dashed border-line bg-surface-soft p-4 sm:flex-row sm:items-center">
            <span aria-label={logoPreview ? "Vista previa del logo de la organización" : "Sin logo cargado"} className="grid size-24 shrink-0 place-items-center overflow-hidden rounded-xl border border-line bg-surface text-ink-muted" role="img">{logoPreview ? <span className="block size-full bg-contain bg-center bg-no-repeat" style={{ backgroundImage: `url(${JSON.stringify(logoPreview)})` }} /> : <ImageUp aria-hidden="true" className="size-7" />}</span>
            <div className="min-w-0 flex-1"><input accept="image/avif,image/jpeg,image/png,image/webp" className="block w-full text-sm text-ink-muted file:mr-4 file:rounded-lg file:border-0 file:bg-accent-button file:px-4 file:py-2.5 file:font-semibold file:text-white hover:file:bg-accent-button-hover" id="logo" name="logo" onChange={(event) => chooseLogo(event.target.files?.[0] ?? null)} ref={logoInput} type="file" />{logoFile ? <Button className="mt-3" onClick={removeLogoSelection} size="sm" variant="ghost"><X className="size-4" />Quitar selección</Button> : null}</div>
          </div>
        </FormField>
      </section>

      <input defaultValue="false" name="truthfulConfirmation" ref={confirmationInput} type="hidden" />
      <div className="flex justify-end border-t border-line pt-6"><Button onClick={openConfirmation}>Guardar cambios</Button></div>

      {confirmationOpen ? <div className="fixed inset-0 z-[80] flex items-start justify-center overflow-y-auto bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setConfirmationOpen(false); }}><div aria-labelledby="organization-confirmation-title" aria-modal="true" className="w-full max-w-lg rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-3"><div><h2 className="text-lg font-bold text-ink" id="organization-confirmation-title">Confirmar datos de la organización</h2><p className="mt-2 text-sm leading-6 text-ink-secondary">¿Confirmás que los datos ingresados son verídicos? Esta información será utilizada en los comprobantes emitidos por tu negocio.</p></div><button aria-label="Cerrar confirmación" className="grid size-8 shrink-0 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft hover:text-ink" onClick={() => setConfirmationOpen(false)} ref={closeButton} type="button"><X className="size-4" /></button></div><div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"><Button onClick={() => setConfirmationOpen(false)} variant="secondary">Cancelar</Button><SubmitButton label="Confirmar y guardar" onClick={confirmAndSubmit} pendingLabel="Guardando cambios…" /></div></div></div> : null}
    </form>
  );
}
