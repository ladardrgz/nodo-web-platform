"use client";

import { X } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { Button } from "@/components/ui/Button";
import { FormField } from "@/components/ui/FormField";

export function CatalogModal({ title, label, open, busy, error, onClose, onSubmit }: { title: string; label: string; open: boolean; busy: boolean; error?: string; onClose: () => void; onSubmit: (name: string) => void }) {
  const [name, setName] = useState(""); const titleId = useId(); const input = useRef<HTMLInputElement>(null);
  const close = () => { setName(""); onClose(); };
  useEffect(() => { if (!open) return; const timer = window.setTimeout(() => { setName(""); input.current?.focus(); }, 20); return () => window.clearTimeout(timer); }, [open]);
  useEffect(() => { if (!open) return; const escape = (event: KeyboardEvent) => { if (event.key === "Escape" && !busy) onClose(); }; document.addEventListener("keydown", escape); return () => document.removeEventListener("keydown", escape); }, [busy, onClose, open]);
  if (!open) return null;
  return <div className="fixed inset-0 z-[90] flex items-start justify-center overflow-y-auto bg-brand-surface/40 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.target === event.currentTarget && !busy) close(); }}><div aria-labelledby={titleId} aria-modal="true" className="w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-center justify-between gap-4"><h2 className="font-bold text-primary" id={titleId}>{title}</h2><button aria-label="Cerrar" className="grid size-8 place-items-center rounded-lg text-muted hover:bg-surface-soft" disabled={busy} onClick={close} type="button"><X className="size-4" /></button></div><form className="mt-5 space-y-5" onSubmit={(event) => { event.preventDefault(); onSubmit(name); }}><FormField error={error} htmlFor="catalog-name" label={label} required><input className="field-control" id="catalog-name" maxLength={80} onChange={(event) => setName(event.target.value)} ref={input} value={name} /></FormField><div className="flex justify-end gap-2"><Button disabled={busy} onClick={close} variant="secondary">Cancelar</Button><Button loading={busy} loadingText="Guardando…" type="submit">Registrar</Button></div></form></div></div>;
}
