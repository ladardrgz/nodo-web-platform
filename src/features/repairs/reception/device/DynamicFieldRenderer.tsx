"use client";

import { FormField } from "@/components/ui/FormField";
import { SearchableSelect } from "@/features/repairs/reception/SearchableSelect";
import { cn } from "@/lib/cn";
import type { CatalogOption, DynamicDeviceField } from "@/features/repairs/reception/types";

export function DynamicFieldRenderer({ field, value, options, disabled, catalogState, catalogError, emptyMessage, onChange }: {
  field: DynamicDeviceField;
  value: string;
  options: CatalogOption[];
  disabled?: boolean;
  catalogState?: "idle" | "loading" | "ready" | "error";
  catalogError?: string;
  emptyMessage?: string;
  onChange: (value: string) => void;
}) {
  const id = `device-field-${field.bindingId}`;
  const component = field.overrides.component;
  const fullWidth = field.overrides.fullWidth || field.fieldType === "TEXTAREA" || field.fieldType === "REPEATABLE";
  if (field.fieldType === "MULTISELECT" || component === "multi-select") {
    let selected: string[] = [];
    try { selected = JSON.parse(value || "[]") as string[]; } catch { selected = []; }
    return <fieldset className={cn(fullWidth && "md:col-span-2")} disabled={disabled}><legend className="mb-2 text-sm font-semibold text-primary">{field.label}</legend>{options.length ? <div className="grid gap-2 sm:grid-cols-2">{options.map((option) => <label className="flex min-h-11 items-center gap-3 rounded-lg border border-border px-3 text-sm text-primary" key={option.id}><input checked={selected.includes(option.id)} className="size-4 accent-accent" onChange={(event) => onChange(JSON.stringify(event.target.checked ? [...selected, option.id] : selected.filter((id) => id !== option.id)))} type="checkbox" />{option.name}</label>)}</div> : <p className="text-sm text-muted">No hay opciones disponibles.</p>}</fieldset>;
  }
  if (field.fieldType === "SELECT" || component === "searchable-select") {
    const loading = catalogState === "loading";
    const placeholder = loading ? "Cargando opciones…" : disabled ? "Primero seleccioná la opción anterior" : options.length ? field.placeholder ?? "Seleccionar" : emptyMessage ?? "No hay opciones disponibles";
    return <div className={cn(fullWidth && "md:col-span-2")}><SearchableSelect id={id} label={field.label} required={field.required} disabled={disabled || loading || options.length === 0} value={value} onChange={onChange} placeholder={placeholder} options={options.map((item) => ({ id: item.id, label: item.name }))} />{catalogState === "error" && catalogError ? <p className="mt-1 text-sm text-danger" role="alert">{catalogError}</p> : catalogState === "ready" && options.length === 0 ? <p className="mt-1 text-sm text-muted">{emptyMessage ?? "No hay opciones disponibles."}</p> : null}</div>;
  }
  if (field.fieldType === "CHECKBOX" || field.fieldType === "SWITCH" || component === "checkbox") {
    return <label className={cn("flex min-h-11 items-center gap-3 rounded-lg border border-border px-3 text-sm font-medium text-primary", fullWidth && "md:col-span-2")} htmlFor={id}><input checked={value === "true"} className="size-4 accent-accent" id={id} onChange={(event) => onChange(String(event.target.checked))} type="checkbox" />{field.label}</label>;
  }
  if (field.fieldType === "RADIO" || component === "radio-group") {
    return <fieldset className={cn(fullWidth && "md:col-span-2")}><legend className="mb-2 text-sm font-semibold text-primary">{field.label}</legend><div className="flex flex-wrap gap-3">{field.options.map((option) => <label className="flex items-center gap-2 text-sm" key={option.id}><input checked={value === option.value} name={id} onChange={() => onChange(option.value)} type="radio" />{option.label}</label>)}</div></fieldset>;
  }
  return <div className={cn(fullWidth && "md:col-span-2")}><FormField htmlFor={id} label={field.label} required={field.required}>{field.fieldType === "TEXTAREA" ? <textarea className="field-control min-h-24" id={id} value={value} onChange={(event) => onChange(event.target.value)} /> : <input className="field-control" id={id} inputMode={field.fieldType === "NUMBER" ? "numeric" : undefined} type={field.fieldType === "NUMBER" ? "number" : "text"} value={value} onChange={(event) => onChange(event.target.value)} />}</FormField></div>;
}
