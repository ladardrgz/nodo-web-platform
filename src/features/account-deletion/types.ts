import type { ActionFeedbackState } from "@/lib/feedback/types";

export type DeletionSubject = "ORGANIZATION" | "CUSTOMER_ACCOUNT";

export interface DeletionBlocker {
  code: string;
  count: number;
  message: string;
}

export interface DeletionActionState extends ActionFeedbackState {
  blockers?: DeletionBlocker[];
  completed?: boolean;
}

export const initialDeletionState: DeletionActionState = { status: "idle" };

export interface PendingDeletion {
  id: string;
  subject_type: DeletionSubject;
  organization_id: string | null;
  reason: string;
  requested_at: string;
  scheduled_for: string;
}
