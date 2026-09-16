"use client";

import { Check, ChevronsUpDown, Plus, Search } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";

import { cn } from "@/lib/cn";

export interface SearchOption {
  id: string;
  label: string;
  group?: string;
  subtitle?: string;
}

interface SearchableSelectProps {
  id: string;
  label: string;
  options: SearchOption[];
  value: string;
  placeholder: string;
  error?: string;
  disabled?: boolean;
  required?: boolean;
  createLabel?: string;
  onCreate?: () => void;
  onChange: (value: string) => void;
}

export function SearchableSelect({
  id,
  label,
  options,
  value,
  placeholder,
  error,
  disabled,
  required = true,
  createLabel,
  onCreate,
  onChange,
}: SearchableSelectProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  const root = useRef<HTMLDivElement>(null);

  // Las respuestas de catálogo pueden incluir una opción recién creada junto a
  // la misma opción revalidada por el servidor. Conservamos una única entrada
  // por id para evitar claves duplicadas y renders inconsistentes.
  const uniqueOptions = useMemo(() => {
    const byId = new Map<string, SearchOption>();
    for (const option of options) {
      if (!byId.has(option.id)) byId.set(option.id, option);
    }
    return [...byId.values()];
  }, [options]);

  const selected = uniqueOptions.find((option) => option.id === value);

  const normalizedQuery = query.trim().toLocaleLowerCase("es");

  const filtered = useMemo(
    () =>
      uniqueOptions.filter((option) =>
        [option.label, option.subtitle ?? "", option.group ?? ""]
          .join(" ")
          .toLocaleLowerCase("es")
          .includes(normalizedQuery),
      ),
    [uniqueOptions, normalizedQuery],
  );

  useEffect(() => {
    const close = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) {
        setOpen(false);
        setQuery("");
      }
    };

    document.addEventListener("pointerdown", close);

    return () => {
      document.removeEventListener("pointerdown", close);
    };
  }, []);

  useEffect(() => {
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        setQuery("");
      }
    };

    document.addEventListener("keydown", escape);

    return () => {
      document.removeEventListener("keydown", escape);
    };
  }, []);

  function selectOption(optionId: string) {
    onChange(optionId);
    setOpen(false);
    setQuery("");
  }

  function handleCreate() {
    setOpen(false);
    setQuery("");
    onCreate?.();
  }

  return (
    <div ref={root} className="relative space-y-2">
      <label
        className="block text-sm font-semibold text-primary"
        id={`${id}-label`}
      >
        {label}

        {required ? <span className="ml-1 text-danger">*</span> : null}
      </label>

      <button
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-labelledby={`${id}-label`}
        className={cn(
          "field-control flex items-center justify-between gap-3 text-left",
          !selected && "text-muted",
          error && "field-control-invalid",
        )}
        disabled={disabled}
        onClick={() => setOpen((current) => !current)}
        type="button"
      >
        <span className="min-w-0 flex-1 truncate">
          {selected?.label ?? placeholder}
        </span>

        <ChevronsUpDown
          aria-hidden="true"
          className="size-4 shrink-0 text-muted"
        />
      </button>

      {error ? (
        <p className="text-sm font-medium text-danger" id={`${id}-error`}>
          {error}
        </p>
      ) : null}

      {open ? (
        <div
          className="
            absolute
            inset-x-0
            top-full
            z-50
            mt-2
            overflow-hidden
            rounded-xl
            border
            border-line
            bg-surface-raised
            shadow-[0_18px_50px_rgb(var(--shadow-color)/25%)]
          "
        >
          {/* Buscador fijo */}
          <div className="border-b border-line p-2">
            <div className="relative">
              <input
                aria-label={`Buscar ${label.toLowerCase()}`}
                autoFocus
                className="
                  field-control
                  min-h-10
                  py-2
                  pl-3
                  pr-10
                  text-sm
                "
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Escribí para buscar…"
                value={query}
              />

              <Search
                aria-hidden="true"
                className="
                  pointer-events-none
                  absolute
                  right-3
                  top-1/2
                  size-4
                  -translate-y-1/2
                  text-muted
                "
              />
            </div>
          </div>

          {/* Lista con scroll independiente */}
          <div
            className="
              max-h-[min(320px,55vh)]
              overflow-y-auto
              overscroll-contain
              p-2
              [scrollbar-gutter:stable]
            "
            role="listbox"
          >
            {filtered.map((option, index) => {
              const showGroup =
                index === 0 || option.group !== filtered[index - 1]?.group;

              return (
                <div key={option.id}>
                  {showGroup ? (
                    <p className="px-3 pb-1 pt-2 text-[10px] font-bold uppercase tracking-wider text-muted">
                      {option.group ?? "Opciones"}
                    </p>
                  ) : null}

                  <button
                    aria-selected={option.id === value}
                    className={cn(
                      `
                      flex
                      w-full
                      items-start
                      gap-2.5
                      rounded-lg
                      px-3
                      py-2.5
                      text-left
                      text-sm
                      text-primary
                      transition-colors
                      hover:bg-surface-hover
                      focus-visible:outline-2
                      focus-visible:outline-accent
                    `,
                      option.id === value && "bg-accent-soft text-accent",
                    )}
                    onClick={() => selectOption(option.id)}
                    role="option"
                    type="button"
                  >
                    <Check
                      aria-hidden="true"
                      className={cn(
                        "mt-0.5 size-4 shrink-0",
                        option.id === value
                          ? "text-accent opacity-100"
                          : "opacity-0",
                      )}
                    />

                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium">
                        {option.label}
                      </span>

                      {option.subtitle ? (
                        <span className="mt-0.5 block truncate text-xs text-muted">
                          {option.subtitle}
                        </span>
                      ) : null}
                    </span>
                  </button>
                </div>
              );
            })}

            {filtered.length === 0 ? (
              <p className="px-3 py-5 text-center text-sm text-muted">
                No encontramos coincidencias.
              </p>
            ) : null}
          </div>

          {/* Acción fija inferior */}
          {onCreate ? (
            <div className="border-t border-line p-2">
              <button
                className="
                  flex
                  min-h-10
                  w-full
                  items-center
                  gap-2
                  rounded-lg
                  px-3
                  text-left
                  text-sm
                  font-semibold
                  text-accent
                  transition-colors
                  hover:bg-surface-hover
                "
                onClick={handleCreate}
                type="button"
              >
                <Plus aria-hidden="true" className="size-4 shrink-0" />

                {createLabel}
              </button>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
