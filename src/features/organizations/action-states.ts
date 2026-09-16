import type { ActionFeedbackState } from "@/lib/feedback/types";

export interface OrganizationStepOneActionState extends ActionFeedbackState {
  completedStep?: 1;
  fieldErrors?: Partial<Record<"legalName" | "commercialName" | "logo", string[]>>;
}
export const initialOrganizationStepOneState: OrganizationStepOneActionState = { status: "idle" };

export interface OrganizationStepTwoActionState extends ActionFeedbackState {
  completedStep?: 2;
  fieldErrors?: Partial<Record<"phone" | "contactEmail", string[]>>;
}
export const initialOrganizationStepTwoState: OrganizationStepTwoActionState = { status: "idle" };

type LocationField = "countryId" | "provinceId" | "localityId" | "neighborhoodId" | "street" | "streetNumber" | "floor" | "apartment" | "postalCode" | "reference";
export interface OrganizationStepThreeActionState extends ActionFeedbackState {
  completedStep?: 3;
  fieldErrors?: Partial<Record<LocationField, string[]>>;
}
export const initialOrganizationStepThreeState: OrganizationStepThreeActionState = { status: "idle" };

export type IncompleteSetupSection = "ORGANIZATION" | "CONTACT" | "LOCATION";
export interface FinalizeInitialSetupState extends ActionFeedbackState {
  incompleteSection?: IncompleteSetupSection;
}
export const initialFinalizeInitialSetupState: FinalizeInitialSetupState = { status: "idle" };

type SettingsField = "name" | "phoneCountry" | "phoneNationalNumber" | "contactEmail" | "countryId" | "provinceId" | "localityId" | "neighborhoodId" | "addressLine" | "logo";
export interface OrganizationSetupActionState extends ActionFeedbackState {
  fieldErrors?: Partial<Record<SettingsField, string[]>>;
  requiresPersonalPhoneConfirmation?: boolean;
}
export const initialOrganizationSetupState: OrganizationSetupActionState = { status: "idle" };
