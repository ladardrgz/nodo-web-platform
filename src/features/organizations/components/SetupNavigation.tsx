import { ArrowLeft, ArrowRight, CheckCircle2 } from "lucide-react";

import { Button } from "@/components/ui/Button";

interface SetupNavigationProps {
  currentStep: number;
  lastStep: number;
  onBack: () => void;
  onContinue: () => void;
}

export function SetupNavigation({ currentStep, lastStep, onBack, onContinue }: SetupNavigationProps) {
  const finalStep = currentStep === lastStep;

  return (
    <div className="flex flex-col-reverse gap-3 border-t border-line pt-5 sm:flex-row sm:items-center sm:justify-between">
      {currentStep > 0 ? (
        <Button className="w-full sm:w-auto" onClick={onBack} variant="secondary">
          <ArrowLeft className="size-4" />
          Volver
        </Button>
      ) : <span aria-hidden="true" />}

      {finalStep ? (
        <Button className="w-full sm:w-auto" disabled>
          <CheckCircle2 className="size-4" />
          Finalizar configuración
        </Button>
      ) : (
        <Button className="w-full sm:w-auto" onClick={onContinue}>
          Continuar
          <ArrowRight className="size-4" />
        </Button>
      )}
    </div>
  );
}
