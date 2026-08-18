"use client";

import { useEffect } from "react";

import { useToast } from "@/components/feedback/ToastProvider";
import type { AuthActionState } from "@/features/auth/schemas";

export function AuthStateFeedback({ state }: { state: AuthActionState }) {
  const { showToast } = useToast();
  useEffect(() => { if (state.status !== "idle" && state.message) showToast(state.message, state.status === "success" ? "success" : "error"); }, [showToast, state]);
  if (!state.message) return null;
  return <p aria-live="polite" className={state.status === "success" ? "rounded-lg border border-success/35 bg-success-soft p-3 text-sm text-success" : "rounded-lg border border-danger/35 bg-danger-soft p-3 text-sm text-danger"}>{state.message}</p>;
}
