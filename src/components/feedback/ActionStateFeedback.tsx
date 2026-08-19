"use client";

import { useEffect, useRef } from "react";

import { useToast } from "@/components/feedback/ToastProvider";
import type { ActionFeedbackState } from "@/lib/feedback/types";

export function ActionStateFeedback({ state }: { state: ActionFeedbackState }) {
  const { toast } = useToast();
  const lastState = useRef<ActionFeedbackState | null>(null);

  useEffect(() => {
    if (state === lastState.current || !state.feedback) return;
    lastState.current = state;
    toast(state.feedback);
  }, [state, toast]);

  return null;
}
