import type { ReceptionCustomer } from "@/features/repairs/reception/types";

export type WizardErrors = Record<string, string | undefined>;
export type CustomerDraft = Omit<ReceptionCustomer, "id">;

