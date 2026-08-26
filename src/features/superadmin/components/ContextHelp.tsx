"use client";

import { CircleHelp, X } from "lucide-react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";

export function ContextHelp({ label, title, children }: { label: string; title: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const titleId = useId();
  const dialogId = useId();
  const triggerRef = useRef<HTMLButtonElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    closeRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Tab") {
        event.preventDefault();
        closeRef.current?.focus();
      }
      if (event.key === "Escape") {
        setOpen(false);
        triggerRef.current?.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [open]);

  const close = () => {
    setOpen(false);
    triggerRef.current?.focus();
  };

  return (
    <span className="inline-flex">
      <button aria-controls={dialogId} aria-expanded={open} aria-label={label} className="group grid size-8 place-items-center rounded-full border border-line bg-surface text-ink-muted shadow-sm transition hover:border-accent/40 hover:bg-accent-soft hover:text-accent" onClick={() => setOpen(true)} ref={triggerRef} type="button"><CircleHelp className="size-[18px] transition-transform group-hover:scale-105" /></button>
      {open ? <span className="fixed inset-0 z-[70] flex items-start justify-center bg-brand-surface/15 px-4 pt-20 backdrop-blur-[1px] sm:pt-24" onPointerDown={(event) => { if (event.currentTarget === event.target) close(); }}><span aria-labelledby={titleId} aria-modal="true" className="block w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 text-left shadow-[0_22px_70px_rgb(var(--shadow-color)/24%)]" id={dialogId} role="dialog"><span className="flex items-start justify-between gap-3"><span><span className="block text-xs font-bold uppercase tracking-[0.14em] text-accent">Ayuda</span><strong className="mt-1 block text-base text-ink" id={titleId}>{title}</strong></span><button aria-label="Cerrar ayuda" className="grid size-8 shrink-0 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft hover:text-ink" onClick={close} ref={closeRef} type="button"><X className="size-4" /></button></span><span className="mt-3 block text-sm leading-6 text-ink-secondary">{children}</span></span></span> : null}
    </span>
  );
}
