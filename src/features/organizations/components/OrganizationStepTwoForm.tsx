"use client";

import { Mail } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useState, type FormEvent } from "react";
import PhoneInput, { type Value } from "react-phone-number-input";
import es from "react-phone-number-input/locale/es";

import { useToast } from "@/components/feedback/ToastProvider";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { normalizeContactEmail, organizationStepTwoSchema } from "@/features/organizations/schemas";
import {
  initialOrganizationStepTwoState,
  saveOrganizationStepTwoAction,
  type OrganizationStepTwoActionState,
} from "@/features/organizations/step-two-actions";
import { cn } from "@/lib/cn";
import type { OwnerOrganization } from "@/types/organization";

type FieldName = "phone" | "contactEmail";
type FieldErrors = Partial<Record<FieldName, string>>;

function validationErrors(values: Record<FieldName, string>): FieldErrors {
  const result = organizationStepTwoSchema.safeParse(values);
  if (result.success) return {};
  const fields = result.error.flatten().fieldErrors;
  return { phone: fields.phone?.[0], contactEmail: fields.contactEmail?.[0] };
}

function describedBy(...ids: Array<string | false | undefined>): string | undefined {
  const value = ids.filter(Boolean).join(" ");
  return value || undefined;
}

interface OrganizationStepTwoFormProps {
  completedInitially: boolean;
  onBack: () => void;
  onSaved: () => void;
  organization: OwnerOrganization;
}

export function OrganizationStepTwoForm({ completedInitially, onBack, onSaved, organization }: OrganizationStepTwoFormProps) {
  const router = useRouter();
  const { toast } = useToast();
  const [values, setValues] = useState<Record<FieldName, string>>({
    phone: organization.phone ?? "",
    contactEmail: organization.contact_email ?? "",
  });
  const [touched, setTouched] = useState<Set<FieldName>>(new Set());
  const [clientErrors, setClientErrors] = useState<FieldErrors>({});
  const [state, action] = useActionState(async (previous: OrganizationStepTwoActionState, formData: FormData) => {
    const next = await saveOrganizationStepTwoAction(previous, formData);
    if (next.feedback) toast(next.feedback);
    if (next.status === "success") {
      onSaved();
      router.refresh();
    }
    return { ...next, feedback: undefined };
  }, initialOrganizationStepTwoState);

  const fieldError = (field: FieldName) => (
    Object.hasOwn(clientErrors, field) ? clientErrors[field] : state.fieldErrors?.[field]?.[0]
  );

  const updateField = (field: FieldName, value: string) => {
    const nextValues = { ...values, [field]: value };
    setValues(nextValues);
    if (touched.has(field)) {
      setClientErrors((current) => ({ ...current, [field]: validationErrors(nextValues)[field] }));
    }
  };

  const blurField = (field: FieldName) => {
    const nextValues = field === "contactEmail"
      ? { ...values, contactEmail: normalizeContactEmail(values.contactEmail) }
      : values;
    setValues(nextValues);
    setTouched((current) => new Set(current).add(field));
    setClientErrors((current) => ({ ...current, [field]: validationErrors(nextValues)[field] }));
  };

  const validateSubmit = (event: FormEvent<HTMLFormElement>) => {
    const errors = validationErrors(values);
    if (Object.values(errors).some(Boolean)) {
      event.preventDefault();
      setTouched(new Set(["phone", "contactEmail"]));
      setClientErrors(errors);
      toast({ variant: "error", title: "Completá los campos obligatorios antes de continuar." });
      return;
    }
    setClientErrors({});
  };

  return (
    <form action={action} className="space-y-6" noValidate onSubmit={validateSubmit}>
      <div className="flex items-start justify-between gap-3 rounded-xl border border-line bg-surface-soft p-4">
        <div>
          <h3 className="font-semibold text-ink">Canales principales</h3>
          <p className="mt-1 text-sm leading-6 text-ink-muted">Estos datos pertenecen a la organización y pueden coincidir o no con los de tu cuenta.</p>
        </div>
        <ContextHelp label="Ayuda sobre los datos de contacto" title="¿Qué datos debo ingresar?">
          Estos datos identifican los canales principales de contacto de tu taller. El email de contacto no modifica tu correo de acceso a Nodo.
        </ContextHelp>
      </div>

      <div className="grid gap-5 md:grid-cols-2">
        <div className="min-w-0 space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="phone">Teléfono <span className="text-danger">*</span></label>
          <PhoneInput
            aria-describedby={describedBy("phone-help", fieldError("phone") && "phone-error")}
            aria-invalid={Boolean(fieldError("phone"))}
            aria-required="true"
            autoComplete="tel"
            className={cn("owner-phone-input", fieldError("phone") && "owner-phone-input-invalid")}
            countryCallingCodeEditable={false}
            countrySelectProps={{ "aria-label": "País del teléfono" }}
            defaultCountry="AR"
            id="phone"
            international
            labels={es}
            limitMaxLength
            name="phone"
            onBlur={() => blurField("phone")}
            onChange={(value?: Value) => updateField("phone", value ?? "")}
            placeholder="3705 234524"
            value={values.phone}
          />
          <p className="text-xs text-ink-muted" id="phone-help">Argentina seleccionada por defecto · el código +54 se gestiona automáticamente.</p>
          {fieldError("phone") ? <p className="text-sm font-medium text-danger" id="phone-error">{fieldError("phone")}</p> : null}
        </div>

        <div className="min-w-0 space-y-2">
          <label className="block text-sm font-semibold text-ink" htmlFor="contactEmail">Email de contacto <span className="text-danger">*</span></label>
          <div className="input-with-leading-icon relative">
            <Mail aria-hidden="true" className="input-leading-icon" />
            <input
              aria-describedby={describedBy("contactEmail-help", fieldError("contactEmail") && "contactEmail-error")}
              aria-invalid={Boolean(fieldError("contactEmail"))}
              aria-required="true"
              autoComplete="email"
              className={cn("field-control", fieldError("contactEmail") && "field-control-invalid")}
              id="contactEmail"
              inputMode="email"
              maxLength={254}
              name="contactEmail"
              onBlur={() => blurField("contactEmail")}
              onChange={(event) => updateField("contactEmail", event.target.value)}
              placeholder="contacto@empresa.com"
              type="email"
              value={values.contactEmail}
            />
          </div>
          <p className="text-xs text-ink-muted" id="contactEmail-help">Este correo se utilizará como medio de contacto de la organización.</p>
          {fieldError("contactEmail") ? <p className="text-sm font-medium text-danger" id="contactEmail-error">{fieldError("contactEmail")}</p> : null}
        </div>
      </div>

      <div className="flex flex-col-reverse gap-3 border-t border-line pt-5 sm:flex-row sm:items-center sm:justify-between">
        <Button className="w-full sm:w-auto" onClick={onBack} variant="secondary">Volver</Button>
        <SubmitButton
          className="w-full sm:w-auto"
          label={completedInitially ? "Guardar cambios y continuar" : "Guardar y continuar"}
          pendingLabel="Guardando..."
        />
      </div>
    </form>
  );
}
