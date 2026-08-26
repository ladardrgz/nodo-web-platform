"use client";

import { Building2, ImageUp, Mail, MapPin, Phone } from "lucide-react";
import { useActionState } from "react";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { FormField } from "@/components/ui/FormField";
import { SubmitButton } from "@/components/ui/SubmitButton";
import {
  initialOrganizationSetupState,
  saveOrganizationSetupAction,
} from "@/features/organizations/actions";
import type { OwnerOrganization } from "@/types/organization";

interface OrganizationSettingsFormProps {
  organization: OwnerOrganization;
  logoUrl: string | null;
}

export function OrganizationSettingsForm({ organization, logoUrl }: OrganizationSettingsFormProps) {
  const [state, action] = useActionState(saveOrganizationSetupAction, initialOrganizationSetupState);
  const error = (field: string) => state.fieldErrors?.[field]?.[0];

  return (
    <form action={action} className="space-y-6">
      <ActionStateFeedback state={state} />

      <div className="grid gap-5 md:grid-cols-2">
        <FormField error={error("name")} htmlFor="name" label="Nombre del negocio u organización" required>
          <div className="input-with-leading-icon relative"><Building2 className="input-leading-icon" /><input aria-invalid={Boolean(error("name"))} className="field-control" defaultValue={organization.name} id="name" maxLength={120} name="name" placeholder="Ej: Nodo Service Tech" required /></div>
        </FormField>
        <FormField error={error("tradeName")} htmlFor="tradeName" label="Nombre comercial" required>
          <input aria-invalid={Boolean(error("tradeName"))} className="field-control" defaultValue={organization.trade_name ?? ""} id="tradeName" maxLength={120} name="tradeName" placeholder="Ej: Nodo Reparaciones" required />
        </FormField>
        <FormField error={error("phone")} htmlFor="phone" label="Teléfono" required>
          <div className="input-with-leading-icon relative"><Phone className="input-leading-icon" /><input aria-invalid={Boolean(error("phone"))} autoComplete="tel" className="field-control" defaultValue={organization.phone ?? ""} id="phone" maxLength={30} name="phone" placeholder="Ej: +54 370 4000000" required type="tel" /></div>
        </FormField>
        <FormField error={error("contactEmail")} htmlFor="contactEmail" label="Email de contacto" required>
          <div className="input-with-leading-icon relative"><Mail className="input-leading-icon" /><input aria-invalid={Boolean(error("contactEmail"))} autoComplete="email" className="field-control" defaultValue={organization.contact_email ?? ""} id="contactEmail" maxLength={254} name="contactEmail" placeholder="Ej: contacto@negocio.com" required type="email" /></div>
        </FormField>
        <FormField error={error("address")} htmlFor="address" label="Dirección" required>
          <div className="input-with-leading-icon relative"><MapPin className="input-leading-icon" /><input aria-invalid={Boolean(error("address"))} autoComplete="street-address" className="field-control" defaultValue={organization.address ?? ""} id="address" maxLength={180} name="address" placeholder="Ej: Av. Principal 123" required /></div>
        </FormField>
        <div className="grid gap-5 sm:grid-cols-2">
          <FormField error={error("locality")} htmlFor="locality" label="Localidad" required><input aria-invalid={Boolean(error("locality"))} autoComplete="address-level2" className="field-control" defaultValue={organization.locality ?? ""} id="locality" maxLength={100} name="locality" placeholder="Ej: Formosa" required /></FormField>
          <FormField error={error("province")} htmlFor="province" label="Provincia" required><input aria-invalid={Boolean(error("province"))} autoComplete="address-level1" className="field-control" defaultValue={organization.province ?? ""} id="province" maxLength={100} name="province" placeholder="Ej: Formosa" required /></FormField>
        </div>
      </div>

      <FormField error={error("description")} htmlFor="description" label="Breve descripción" required hint="Entre 10 y 600 caracteres.">
        <textarea aria-invalid={Boolean(error("description"))} className="field-control min-h-28 resize-y" defaultValue={organization.description ?? ""} id="description" maxLength={600} minLength={10} name="description" placeholder="Contá brevemente qué servicios ofrece tu organización." required />
      </FormField>

      <FormField error={error("logo")} htmlFor="logo" label="Logo" hint="JPG, PNG o WebP. Máximo 2 MB. Si ya tenés uno, solo elegí otro archivo para reemplazarlo.">
        <div className="flex flex-col gap-4 rounded-xl border border-dashed border-border bg-surface-soft p-4 sm:flex-row sm:items-center">
          <span aria-label={logoUrl ? "Logo actual de la organización" : "Sin logo cargado"} className="grid size-20 shrink-0 place-items-center rounded-xl border border-border bg-surface bg-contain bg-center bg-no-repeat text-muted" role="img" style={logoUrl ? { backgroundImage: `url(${JSON.stringify(logoUrl)})` } : undefined}><ImageUp className="size-7" /></span>
          <input accept="image/jpeg,image/png,image/webp" className="block w-full text-sm text-muted file:mr-4 file:rounded-lg file:border-0 file:bg-accent file:px-4 file:py-2.5 file:font-semibold file:text-white hover:file:bg-accent-strong" id="logo" name="logo" type="file" />
        </div>
      </FormField>

      <div className="flex justify-end border-t border-border pt-6">
        <SubmitButton label={organization.initial_setup_completed ? "Guardar cambios" : "Completar configuración"} pendingLabel="Guardando configuración..." />
      </div>
    </form>
  );
}
