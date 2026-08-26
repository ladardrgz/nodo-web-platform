"use client";

import {
  Building2,
  ClipboardCheck,
  MapPin,
  Phone,
} from "lucide-react";
import { useState } from "react";

import { Card } from "@/components/ui/Card";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { OrganizationStepOneForm } from "@/features/organizations/components/OrganizationStepOneForm";
import { OrganizationStepTwoForm } from "@/features/organizations/components/OrganizationStepTwoForm";
import { OrganizationStepThreeForm } from "@/features/organizations/components/OrganizationStepThreeForm";
import { OrganizationStepFourConfirmation } from "@/features/organizations/components/OrganizationStepFourConfirmation";
import { SetupStepper } from "@/features/organizations/components/SetupStepper";
import type { SetupStepDefinition } from "@/features/organizations/components/SetupStep";
import { canSelectSetupStep, highestUnlockedSetupStep } from "@/features/organizations/setup-wizard-state";
import type { OwnerOrganization } from "@/types/organization";
import type { InitialSetupConfirmationData, InitialSetupLocationData } from "@/types/geography";

const steps: readonly SetupStepDefinition[] = [
  { id: "organization", number: "01", title: "Organización", description: "Configurá la identidad de tu espacio de trabajo.", icon: Building2 },
  { id: "contact", number: "02", title: "Contacto", description: "Definí cómo podrán comunicarse con tu organización.", icon: Phone },
  { id: "location", number: "03", title: "Ubicación", description: "Indicá dónde funciona tu taller o espacio de trabajo.", icon: MapPin },
  { id: "confirmation", number: "04", title: "Confirmación", description: "Revisá la información antes de habilitar tu espacio de trabajo.", icon: ClipboardCheck },
];

export function InitialSetupWizard({ confirmationData, locationData, logoUrl, organization }: { confirmationData: InitialSetupConfirmationData; locationData: InitialSetupLocationData; logoUrl: string | null; organization: OwnerOrganization }) {
  const initialStepIndex = Math.min(Math.max(organization.initial_setup_step - 1, 0), steps.length - 1);
  const [currentStep, setCurrentStep] = useState(initialStepIndex);
  const [completedSteps, setCompletedSteps] = useState<Set<number>>(
    () => new Set(Array.from({ length: initialStepIndex }, (_, index) => index)),
  );
  const highestUnlockedStep = highestUnlockedSetupStep(completedSteps, steps.length);
  const step = steps[currentStep];

  const selectStep = (index: number) => {
    if (canSelectSetupStep(index, completedSteps, steps.length)) setCurrentStep(index);
  };

  const completeOrganizationStep = () => {
    setCompletedSteps((current) => new Set(current).add(0));
    setCurrentStep(1);
  };

  const completeContactStep = () => {
    setCompletedSteps((current) => new Set(current).add(1));
    setCurrentStep(2);
  };

  const completeLocationStep = () => {
    setCompletedSteps((current) => new Set(current).add(2));
    setCurrentStep(3);
  };

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <header className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.14em] text-accent">Primeros pasos</p>
          <h1 className="mt-2 text-2xl font-bold tracking-tight text-primary sm:text-3xl">Configuración inicial</h1>
          <p className="mt-2 max-w-2xl text-sm leading-6 text-muted">
            Prepará tu organización mediante un recorrido breve y ordenado.
          </p>
        </div>
        <ContextHelp label="Ayuda sobre la configuración inicial" title="¿Por qué debo completar esta configuración?">
          Estos datos permiten preparar tu espacio de trabajo y personalizar Nodo para tu organización. Hasta completar los pasos obligatorios, las funciones operativas permanecerán bloqueadas.
        </ContextHelp>
      </header>

      <div className="grid gap-5 lg:grid-cols-[280px_minmax(0,1fr)] lg:items-start">
        <Card className="p-3 sm:p-4 lg:sticky lg:top-24">
          <div className="mb-3 flex items-center justify-between border-b border-line px-2 pb-3">
            <span className="text-xs font-bold uppercase tracking-[0.12em] text-ink-muted">Progreso</span>
            <span aria-live="polite" className="text-xs font-semibold text-ink-secondary">Paso {currentStep + 1} de {steps.length}</span>
          </div>
          <SetupStepper
            completedSteps={completedSteps}
            currentStep={currentStep}
            highestUnlockedStep={highestUnlockedStep}
            onSelect={selectStep}
            steps={steps}
          />
        </Card>

        <Card className="min-w-0 overflow-hidden">
          <section aria-labelledby={`setup-step-${step.id}`} className="p-5 sm:p-7 lg:p-8">
            <div className="flex items-start gap-4">
              <span className="grid size-11 shrink-0 place-items-center rounded-xl bg-accent-soft text-accent">
                <step.icon aria-hidden="true" className="size-5" />
              </span>
              <div className="min-w-0">
                <p className="text-xs font-bold uppercase tracking-[0.13em] text-accent">Paso {step.number}</p>
                <h2 className="mt-1 text-xl font-bold text-ink sm:text-2xl" id={`setup-step-${step.id}`}>{step.title}</h2>
                <p className="mt-2 text-sm leading-6 text-ink-muted">{step.description}</p>
              </div>
            </div>

            <div className="my-6 h-px bg-line" />
            {currentStep === 0 ? (
              <OrganizationStepOneForm
                completedInitially={organization.initial_setup_step > 1}
                logoUrl={logoUrl}
                onSaved={completeOrganizationStep}
                organization={organization}
              />
            ) : currentStep === 1 ? (
              <OrganizationStepTwoForm
                completedInitially={organization.initial_setup_step > 2}
                onBack={() => setCurrentStep(0)}
                onSaved={completeContactStep}
                organization={organization}
              />
            ) : currentStep === 2 ? (
              <OrganizationStepThreeForm
                completedInitially={organization.initial_setup_step > 3}
                locationData={locationData}
                onBack={() => setCurrentStep(1)}
                onSaved={completeLocationStep}
              />
            ) : (
              <OrganizationStepFourConfirmation
                confirmationData={confirmationData}
                logoUrl={logoUrl}
                onBack={() => setCurrentStep(2)}
                onEdit={setCurrentStep}
                organization={organization}
              />
            )}
          </section>
        </Card>
      </div>
    </div>
  );
}
