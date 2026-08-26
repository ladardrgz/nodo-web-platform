"use client";

import { Settings2, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";

import { ActionStateFeedback } from "@/components/feedback/ActionStateFeedback";
import { Button } from "@/components/ui/Button";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { saveQuickLinksAction, type QuickLinksActionState } from "@/features/quick-links/actions";
import { BrandIcon } from "@/features/quick-links/components/BrandIcon";
import {
  QUICK_LINK_CONFIG,
  QUICK_LINK_SERVICES,
  type QuickLinkItem,
  type QuickLinkService,
} from "@/features/quick-links/config";
import { validateQuickLinkUrl } from "@/features/quick-links/validation";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { cn } from "@/lib/cn";

const initialState: QuickLinksActionState = { status: "idle" };
type Values = Record<QuickLinkService, { url: string; enabled: boolean }>;

function valuesFromLinks(links: QuickLinkItem[]): Values {
  const values = Object.fromEntries(
    QUICK_LINK_SERVICES.map((service) => [service, { url: "", enabled: true }]),
  ) as Values;

  links.forEach((link) => {
    values[link.service] = { url: link.url, enabled: link.enabled };
  });
  return values;
}

export function QuickAccessBar({ links, configurable }: { links: QuickLinkItem[]; configurable: boolean }) {
  const router = useRouter();
  const initialValues = useMemo(() => valuesFromLinks(links), [links]);
  const [values, setValues] = useState(initialValues);
  const [open, setOpen] = useState(false);
  const configurationButtonRef = useRef<HTMLButtonElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const [touched, setTouched] = useState<Set<QuickLinkService>>(new Set());
  const [clientErrors, setClientErrors] = useState<Partial<Record<QuickLinkService, string>>>({});
  const [state, action] = useActionState(async (previous: QuickLinksActionState, formData: FormData) => {
    const next = await saveQuickLinksAction(previous, formData);
    if (next.status === "success") {
      setOpen(false);
      setTouched(new Set());
      router.refresh();
    }
    return next;
  }, initialState);

  useEffect(() => {
    if (!open) return;

    const previousOverflow = document.body.style.overflow;
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        configurationButtonRef.current?.focus();
        return;
      }
      if (event.key !== "Tab") return;
      const focusable = dialogRef.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]), input:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])',
      );
      if (!focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", close);
    dialogRef.current?.querySelector<HTMLElement>("button")?.focus();
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", close);
    };
  }, [open]);

  const validate = (service: QuickLinkService, url: string) => {
    if (!url.trim()) return "";
    try {
      validateQuickLinkUrl(service, url);
      return "";
    } catch (error) {
      return error instanceof Error ? error.message : "Ingresá una URL válida.";
    }
  };

  const update = (service: QuickLinkService, url: string) => {
    setValues((current) => ({ ...current, [service]: { ...current[service], url } }));
    if (touched.has(service)) {
      setClientErrors((current) => ({ ...current, [service]: validate(service, url) }));
    }
  };

  const openConfiguration = () => {
    if (!configurable) return;
    setValues(initialValues);
    setClientErrors({});
    setTouched(new Set());
    setOpen(true);
  };

  const visibleLinks = QUICK_LINK_SERVICES.flatMap((service) => {
    const item = links.find((link) => link.service === service);
    return item?.enabled && item.url ? [{ ...item, service }] : [];
  });

  const modal = open ? (
    <div
      className="fixed inset-0 z-[100] overflow-y-auto bg-brand-surface/40 backdrop-blur-sm"
      onPointerDown={() => {
        setOpen(false);
        configurationButtonRef.current?.focus();
      }}
    >
      <div className="flex min-h-full items-center justify-center p-4 sm:p-8">
        <div
          aria-labelledby="quick-links-title"
          aria-modal="true"
          className="w-full max-w-2xl overflow-hidden rounded-xl border border-line bg-surface-raised shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]"
          onPointerDown={(event) => event.stopPropagation()}
          ref={dialogRef}
          role="dialog"
        >
          <div className="flex items-start justify-between gap-3 border-b border-line px-5 py-4">
            <div>
              <h2 className="font-bold text-ink" id="quick-links-title">Configurar accesos rápidos</h2>
              <p className="mt-1 text-xs text-ink-muted">
                Guardá únicamente enlaces HTTPS de los servicios disponibles.
              </p>
            </div>
            <button
              aria-label="Cerrar configuración"
              className="grid size-8 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft hover:text-ink"
              onClick={() => {
                setOpen(false);
                configurationButtonRef.current?.focus();
              }}
              type="button"
            >
              <X className="size-4" />
            </button>
          </div>

          <form action={action}>
            <div className="max-h-[65vh] space-y-3 overflow-y-auto p-5">
              {QUICK_LINK_SERVICES.map((service) => {
                const label = QUICK_LINK_CONFIG[service].label;
                const error = clientErrors[service] || state.fieldErrors?.[service]?.[0];
                return (
                  <div className="rounded-lg border border-line bg-surface-soft p-3" key={service}>
                    <div className="flex items-center gap-3">
                      <span className="quick-access-icon shrink-0">
                        <BrandIcon className="size-[18px]" service={service} />
                      </span>
                      <label className="min-w-0 flex-1">
                        <span className="mb-1.5 block text-xs font-bold text-ink-secondary">{label}</span>
                        <input
                          aria-describedby={error ? `quick-link-error-${service}` : undefined}
                          aria-invalid={Boolean(error)}
                          className={cn("field-control", error && "field-control-invalid")}
                          name={`url_${service}`}
                          onBlur={() => {
                            setTouched((current) => new Set(current).add(service));
                            setClientErrors((current) => ({
                              ...current,
                              [service]: validate(service, values[service].url),
                            }));
                          }}
                          onChange={(event) => update(service, event.target.value)}
                          placeholder={QUICK_LINK_CONFIG[service].example}
                          type="url"
                          value={values[service].url}
                        />
                        <span className="mt-1.5 block break-all text-[11px] text-ink-muted">
                          Ejemplo: {QUICK_LINK_CONFIG[service].example}
                        </span>
                      </label>
                    </div>
                    <label className="mt-2 inline-flex items-center gap-2 text-xs font-semibold text-ink-secondary">
                      <input
                        checked={values[service].enabled && Boolean(values[service].url)}
                        disabled={!values[service].url}
                        name={`enabled_${service}`}
                        onChange={(event) => setValues((current) => ({
                          ...current,
                          [service]: { ...current[service], enabled: event.target.checked },
                        }))}
                        type="checkbox"
                      />
                      Mostrar en accesos rápidos
                    </label>
                    {error ? (
                      <p className="mt-2 text-xs font-semibold text-danger" id={`quick-link-error-${service}`}>
                        {error}
                      </p>
                    ) : null}
                  </div>
                );
              })}
            </div>
            <div className="flex flex-col-reverse gap-2 border-t border-line px-5 py-4 sm:flex-row sm:justify-end">
              <Button
                onClick={() => {
                  setValues(initialValues);
                  setOpen(false);
                  configurationButtonRef.current?.focus();
                }}
                variant="secondary"
              >
                Cancelar
              </Button>
              <SubmitButton label="Guardar accesos" pendingLabel="Guardando accesos…" />
            </div>
          </form>
        </div>
      </div>
    </div>
  ) : null;

  return (
    <div className="min-w-0">
      <ActionStateFeedback state={state} />
      <div className="flex items-center gap-2">
        <div className="flex shrink-0 items-center gap-1.5">
          <span className="text-[11px] font-bold uppercase tracking-[0.13em] text-ink-muted sm:text-xs">Accesos rápidos</span>
          <ContextHelp label="Ayuda sobre accesos rápidos" title="¿Qué son los accesos rápidos?">
            <span>
              Te permiten guardar accesos a las aplicaciones y servicios que utilizás habitualmente para abrirlos
              rápidamente desde Nodo. Los enlaces son personales y no representan cuentas oficiales de Nodo.
            </span>
            <span className="mt-3 block">
              Nodo no lee tus mensajes ni accede a tus cuentas mediante estos accesos.
            </span>
          </ContextHelp>
        </div>
        <div className="flex min-w-0 flex-1 gap-1.5 overflow-x-auto py-1 [scrollbar-width:none]">
          {visibleLinks.map((item) => {
            const service = item.service;
            const label = QUICK_LINK_CONFIG[service].label;
            return (
              <a
                aria-label={`Abrir ${label}`}
                className="quick-access-icon"
                href={item.url}
                key={service}
                rel="noopener noreferrer"
                target="_blank"
                title={`Abrir ${label}`}
              >
                <BrandIcon className="size-[18px]" service={service} />
              </a>
            );
          })}
        </div>
        <button
          aria-label="Configurar accesos rápidos"
          className="grid size-9 shrink-0 place-items-center rounded-lg border border-line bg-surface text-ink-muted transition hover:border-accent/40 hover:bg-surface-soft hover:text-ink focus-visible:outline-accent disabled:opacity-40"
          disabled={!configurable}
          onClick={openConfiguration}
          ref={configurationButtonRef}
          title="Configurar accesos"
          type="button"
        >
          <Settings2 className="size-4" />
        </button>
      </div>
      {modal ? createPortal(modal, document.body) : null}
    </div>
  );
}
