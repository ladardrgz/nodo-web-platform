"use client";

import { useState, type Dispatch, type SetStateAction } from "react";
import { customerPhoneError, emailError, nameError } from "@/features/repairs/reception/validation/customerValidation";
import type { ReceptionCustomer } from "@/features/repairs/reception/types";
import type { CustomerDraft, WizardErrors } from "@/features/repairs/reception/wizard-types";

export function useCustomerStep(initialCustomers: ReceptionCustomer[], setErrors: Dispatch<SetStateAction<WizardErrors>>) {
  const [customers, setCustomers] = useState(initialCustomers);
  const [customerId, setCustomerId] = useState("");
  const [customer, setCustomer] = useState<CustomerDraft>({ firstName: "", lastName: "", phone: "", email: "" });
  const [touched, setTouched] = useState(new Set<string>());

  const setFieldError = (key: string, value?: string) =>
    setErrors((current) => ({ ...current, [key]: value }));

  function updateCustomer(key: keyof CustomerDraft, value: string) {
    const normalized = key === "phone"
      ? value.replace(/\D/g, "").slice(0, 10)
      : key === "email"
        ? value.toLowerCase().replace(/\s/g, "")
        : value;
    setCustomer((current) => ({ ...current, [key]: normalized }));
    if (touched.has(key)) {
      setFieldError(key, key === "firstName" ? nameError(normalized, "nombre") : key === "lastName" ? nameError(normalized, "apellido") : key === "phone" ? customerPhoneError(normalized) : emailError(normalized));
    }
  }

  function chooseCustomer(id: string) {
    setCustomerId(id);
    setErrors({});
    if (id !== "NEW") {
      const found = customers.find((item) => item.id === id);
      if (found) setCustomer({ firstName: found.firstName, lastName: found.lastName, phone: found.phone, email: found.email });
      return;
    }
    setCustomer({ firstName: "", lastName: "", phone: "", email: "" });
  }

  function validateCustomer() {
    const next: WizardErrors = {};
    if (!customerId) next.customerId = "Seleccioná un cliente o elegí registrar uno nuevo.";
    if (customerId === "NEW") {
      next.firstName = nameError(customer.firstName, "nombre");
      next.lastName = nameError(customer.lastName, "apellido");
      next.phone = customerPhoneError(customer.phone);
      next.email = emailError(customer.email);
    }
    setErrors(next);
    setTouched(new Set(["firstName", "lastName", "phone", "email"]));
    return !Object.values(next).some(Boolean);
  }

  return { customers, setCustomers, customerId, setCustomerId, customer, touched, setTouched, chooseCustomer, updateCustomer, validateCustomer };
}
