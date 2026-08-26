import type { SetupStepDefinition, SetupStepStatus } from "@/features/organizations/components/SetupStep";
import { SetupStep } from "@/features/organizations/components/SetupStep";

interface SetupStepperProps {
  completedSteps: ReadonlySet<number>;
  currentStep: number;
  highestUnlockedStep: number;
  onSelect: (index: number) => void;
  steps: readonly SetupStepDefinition[];
}

function statusFor(index: number, currentStep: number, completedSteps: ReadonlySet<number>): SetupStepStatus {
  if (index === currentStep) return "ACTIVE";
  if (completedSteps.has(index)) return "COMPLETED";
  return "PENDING";
}

export function SetupStepper({ completedSteps, currentStep, highestUnlockedStep, onSelect, steps }: SetupStepperProps) {
  return (
    <nav aria-label="Pasos de configuración inicial">
      <ol className="grid grid-cols-4 gap-1 lg:hidden">
        {steps.map((step, index) => (
          <li className="relative min-w-0" key={step.id}>
            {index < steps.length - 1 ? (
              <span aria-hidden="true" className="absolute left-[calc(50%+1rem)] right-[calc(-50%+1rem)] top-6 h-px bg-line" />
            ) : null}
            <SetupStep
              compact
              enabled={index <= highestUnlockedStep}
              onSelect={() => onSelect(index)}
              status={statusFor(index, currentStep, completedSteps)}
              step={step}
            />
          </li>
        ))}
      </ol>

      <ol className="hidden space-y-1 lg:block">
        {steps.map((step, index) => (
          <li className="relative pb-5 last:pb-0" key={step.id}>
            {index < steps.length - 1 ? (
              <span aria-hidden="true" className="absolute bottom-[-0.25rem] left-[2.05rem] top-12 w-px bg-line" />
            ) : null}
            <SetupStep
              enabled={index <= highestUnlockedStep}
              onSelect={() => onSelect(index)}
              status={statusFor(index, currentStep, completedSteps)}
              step={step}
            />
          </li>
        ))}
      </ol>
    </nav>
  );
}
