"use client";

import { ChevronDown, LoaderCircle } from "lucide-react";

import { cn } from "@/lib/cn";
import type { GeographyOption } from "@/types/geography";

export function GeographySelect({
  disabled,
  error,
  id,
  loading,
  name,
  onBlur,
  onChange,
  options,
  placeholder,
  value,
}: {
  disabled?: boolean;
  error?: string;
  id: string;
  loading?: boolean;
  name: string;
  onBlur?: () => void;
  onChange: (value: string) => void;
  options: GeographyOption[];
  placeholder: string;
  value: string;
}) {
  return (
    <div className="input-with-trailing-icon relative">
      <select
        aria-describedby={error ? `${id}-error` : undefined}
        aria-invalid={Boolean(error)}
        className={cn("field-control appearance-none", error && "field-control-invalid")}
        disabled={disabled || loading}
        id={id}
        name={name}
        onBlur={onBlur}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        <option value="">{loading ? "Cargando..." : placeholder}</option>
        {options.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
      </select>
      {loading
        ? <LoaderCircle aria-hidden="true" className="input-trailing-icon animate-spin" />
        : <ChevronDown aria-hidden="true" className="input-trailing-icon" />}
    </div>
  );
}
