"use client";

import { Check, Circle } from "lucide-react";

const commonPasswords = new Set(["1234567890", "password", "contraseña", "qwerty123", "admin123", "nodo123456"]);

export function passwordRequirements(password: string) {
  const normalized = password.toLocaleLowerCase("es-AR");
  return [
    ["Al menos 12 caracteres", password.length >= 12],
    ["Una letra mayúscula", /[A-Z]/.test(password)],
    ["Una letra minúscula", /[a-z]/.test(password)],
    ["Un número", /\d/.test(password)],
    ["Un símbolo", /[^A-Za-z0-9]/.test(password)],
    ["No ser una contraseña trivial", password.length > 0 && !commonPasswords.has(normalized)],
  ] as const;
}

export function PasswordRequirements({ password }: { password: string }) {
  const requirements = passwordRequirements(password);
  const passed = requirements.filter(([, valid]) => valid).length;
  const label = passed <= 2 ? "Débil" : passed <= 4 ? "Aceptable" : passed === 5 ? "Fuerte" : "Muy fuerte";
  const tone = label === "Débil" ? "bg-danger" : label === "Aceptable" ? "bg-warning" : label === "Fuerte" ? "bg-accent" : "bg-cyan-brand";
  return <div aria-live="polite" className="rounded-lg border border-line bg-surface-soft p-3 text-xs text-muted"><div className="mb-2 flex items-center justify-between gap-3"><strong className="text-ink">Fortaleza: {label}</strong><span>{passed}/6</span></div><div aria-hidden="true" className="mb-3 h-1.5 overflow-hidden rounded-full bg-line"><span className={`block h-full rounded-full transition-all ${tone}`} style={{ width: `${(passed / 6) * 100}%` }} /></div><p className="mb-2 font-semibold text-ink">Tu contraseña debe incluir:</p><ul className="space-y-1">{requirements.map(([label, valid]) => <li className={valid ? "flex items-center gap-2 text-success" : "flex items-center gap-2"} key={label}>{valid ? <Check className="size-3.5" /> : <Circle className="size-3.5" />}{label}</li>)}</ul></div>;
}
