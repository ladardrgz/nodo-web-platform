"use client";

import { useFormStatus } from "react-dom";

import { Button } from "@/components/ui/Button";
import type { ComponentProps } from "react";

interface SubmitButtonProps extends Omit<ComponentProps<typeof Button>, "children" | "loading" | "loadingText" | "type"> {
  label: string;
  pendingLabel: string;
}

export function SubmitButton({ label, pendingLabel, ...props }: SubmitButtonProps) {
  const { pending } = useFormStatus();
  return <Button {...props} loading={pending} loadingText={pendingLabel} type="submit">{label}</Button>;
}
