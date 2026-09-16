"use client";

import { getCountries, getCountryCallingCode, type Country } from "react-phone-number-input";
import es from "react-phone-number-input/locale/es";

import { cn } from "@/lib/cn";

const countries = getCountries()
  .map((code) => ({ code, label: es[code] ?? code, callingCode: getCountryCallingCode(code) }))
  .sort((left, right) => left.label.localeCompare(right.label, "es"));

export function InternationalPhoneField({
  country,
  error,
  nationalNumber,
  onBlur,
  onChange,
}: {
  country: Country;
  error?: string;
  nationalNumber: string;
  onBlur: () => void;
  onChange: (country: Country, nationalNumber: string) => void;
}) {
  const callingCode = getCountryCallingCode(country);
  const maxNationalLength = Math.max(4, 15 - callingCode.length);

  return (
    <div className="grid min-w-0 gap-2 sm:grid-cols-[minmax(190px,0.8fr)_minmax(0,1fr)]">
      <div className="input-with-trailing-icon relative">
        <select
          aria-label="País y prefijo telefónico"
          className={cn("field-control appearance-none", error && "field-control-invalid")}
          id="phoneCountry"
          name="phoneCountry"
          onChange={(event) => onChange(event.target.value as Country, "")}
          value={country}
        >
          {countries.map((item) => <option key={item.code} value={item.code}>+{item.callingCode} {item.label}</option>)}
        </select>
      </div>
      <div className={cn("flex min-w-0 items-stretch rounded-lg border bg-[var(--input-bg)] transition-[border-color,box-shadow] focus-within:border-accent focus-within:ring-[3px] focus-within:ring-accent/15", error ? "border-danger" : "border-line")}>
        <span aria-hidden="true" className="grid shrink-0 place-items-center border-r border-line px-3 text-sm font-semibold text-ink-secondary">+{callingCode}</span>
        <input
          aria-describedby={error ? "phoneNationalNumber-error" : "phoneNationalNumber-help"}
          aria-invalid={Boolean(error)}
          autoComplete="tel-national"
          className="min-h-11 min-w-0 flex-1 bg-transparent px-3 text-ink outline-none placeholder:text-[var(--placeholder)]"
          id="phoneNationalNumber"
          inputMode="numeric"
          maxLength={country === "AR" ? 10 : maxNationalLength}
          name="phoneNationalNumber"
          onBlur={onBlur}
          onChange={(event) => onChange(country, event.target.value.replace(/\D/gu, "").slice(0, country === "AR" ? 10 : maxNationalLength))}
          placeholder="Número nacional"
          value={nationalNumber}
        />
      </div>
    </div>
  );
}
