"use client";

import { FormField } from "@/components/ui/FormField";
import { cn } from "@/lib/cn";
import { SearchableSelect } from "@/features/repairs/reception/SearchableSelect";
import type { ReceptionCustomer } from "@/features/repairs/reception/types";
import type { CustomerDraft, WizardErrors } from "@/features/repairs/reception/wizard-types";

export function CustomerStep({
  customers,
  customerId,
  customer,
  errors,
  chooseCustomer,
  update,
  touch,
}: {
  customers: ReceptionCustomer[];
  customerId: string;
  customer: CustomerDraft;
  errors: WizardErrors;
  chooseCustomer: (id: string) => void;
  update: (key: keyof CustomerDraft, value: string) => void;
  touch: (key: string) => void;
}) {
  return (
    <fieldset>
      <legend className="text-xl font-bold text-primary">
        Paso 1. Identificación del cliente
      </legend>

      <p className="mt-2 text-sm text-muted">
        Buscá un cliente registrado o completá sus datos básicos.
      </p>

      <div className="mt-6 space-y-5">
        <SearchableSelect
          error={errors.customerId}
          id="customerId"
          label="Cliente"
          onChange={chooseCustomer}
          options={customers.map((item) => ({
            id: item.id,
            label: `${item.firstName} ${item.lastName}`,
            subtitle: item.phone,
          }))}
          placeholder="Seleccionar cliente"
          value={customerId}
        />

        <div className="flex">
          <button
            className="
              group
              relative
              inline-flex
              min-h-11
              cursor-pointer
              items-center
              justify-center
              gap-2.5
              rounded-lg
              border-0
              bg-[#212121]
              px-5
              py-3
              text-sm
              font-semibold
              text-white
              outline
              outline-1
              outline-[#353535]
              shadow-[0_0_1em_1em_rgba(0,0,0,0.1)]
              transition-all
              duration-300
              ease-in-out
              hover:scale-[1.04]
              hover:bg-[radial-gradient(circle_at_bottom,rgba(50,100,180,0.5)_10%,#212121_70%)]
              hover:outline-0
              hover:shadow-[0_0_1em_0.45em_rgba(0,0,0,0.1)]
              focus-visible:outline-2
              focus-visible:outline-offset-2
              focus-visible:outline-accent
              active:scale-[0.98]
            "
            onClick={() => chooseCustomer("NEW")}
            type="button"
          >
            <svg
              aria-hidden="true"
              className="
                size-[18px]
                shrink-0
                transition-transform
                duration-300
                ease-in-out
                group-hover:rotate-90
              "
              fill="none"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M12 5V19M5 12H19"
                stroke="currentColor"
                strokeLinecap="round"
                strokeWidth="2.4"
              />
            </svg>

            <span>Registrar nuevo cliente</span>
          </button>
        </div>

        {customerId === "NEW" && (
          <div className="grid gap-4 rounded-xl border border-line bg-surface-soft p-4 sm:grid-cols-2">
            <FormField
              error={errors.firstName}
              htmlFor="firstName"
              label="Nombre"
              required
            >
              <input
                className={cn(
                  "field-control",
                  errors.firstName && "field-control-invalid",
                )}
                id="firstName"
                onBlur={() => touch("firstName")}
                onChange={(event) => update("firstName", event.target.value)}
                value={customer.firstName}
              />
            </FormField>

            <FormField
              error={errors.lastName}
              htmlFor="lastName"
              label="Apellido"
              required
            >
              <input
                className={cn(
                  "field-control",
                  errors.lastName && "field-control-invalid",
                )}
                id="lastName"
                onBlur={() => touch("lastName")}
                onChange={(event) => update("lastName", event.target.value)}
                value={customer.lastName}
              />
            </FormField>

            <FormField
              error={errors.phone}
              hint="Ingresá los 10 dígitos nacionales, sin +54, espacios ni símbolos."
              htmlFor="phone"
              label="Teléfono"
              required
            >
              <input
                className={cn(
                  "field-control",
                  errors.phone && "field-control-invalid",
                )}
                id="phone"
                inputMode="numeric"
                maxLength={10}
                onBlur={() => touch("phone")}
                onChange={(event) => update("phone", event.target.value)}
                value={customer.phone}
              />
            </FormField>

            <FormField
              error={errors.email}
              htmlFor="email"
              label="Correo electrónico"
            >
              <input
                className={cn(
                  "field-control",
                  errors.email && "field-control-invalid",
                )}
                id="email"
                onBlur={() => touch("email")}
                onChange={(event) => update("email", event.target.value)}
                placeholder="correo@dominio.com"
                type="email"
                value={customer.email}
              />
            </FormField>
          </div>
        )}
      </div>
    </fieldset>
  );
}


