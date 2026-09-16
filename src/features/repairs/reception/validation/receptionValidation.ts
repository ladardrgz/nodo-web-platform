import type { WizardErrors } from "@/features/repairs/reception/wizard-types";

export function validateReception(reportedProblem: string): WizardErrors {
  const errors: WizardErrors = {};
  if (reportedProblem.trim().length < 10)
    errors.reportedProblem = "Describí el problema informado con al menos 10 caracteres.";
  return errors;
}
