"use client";

import { CheckCircle2, CircleAlert, Info, TriangleAlert, X } from "lucide-react";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";

import { cn } from "@/lib/cn";
import type { ToastOptions, ToastVariant } from "@/lib/feedback/types";

interface ToastItem extends Required<Pick<ToastOptions, "title" | "variant" | "duration">> {
  id: number;
  description?: string;
  exiting: boolean;
}

interface ToastContextValue {
  toast: (options: ToastOptions) => number;
  dismissToast: (id: number) => void;
}

const DEFAULT_DURATION = 5000;
const EXIT_DURATION = 180;
const ToastContext = createContext<ToastContextValue | null>(null);

const queryFeedback: Record<string, ToastOptions> = {
  session_started: { variant: "success", title: "Sesión iniciada", description: "Ingresaste correctamente a Nodo." },
  account_created: { variant: "success", title: "Cuenta creada", description: "Te enviamos un correo para confirmar tu cuenta de Nodo." },
  password_changed: { variant: "success", title: "Contraseña actualizada", description: "Tu contraseña se cambió correctamente." },
  signed_out: { variant: "info", title: "Sesión cerrada", description: "Cerraste tu sesión de forma segura." },
  session_expired: { variant: "warning", title: "Tu sesión venció", description: "Volvé a iniciar sesión para continuar." },
  callback_failed: { variant: "error", title: "No pudimos completar el acceso", description: "El enlace no es válido o ya venció." },
  confirmation_failed: { variant: "error", title: "No pudimos verificar el correo", description: "Solicitá un enlace nuevo e intentá nuevamente." },
  invalid_confirmation: { variant: "error", title: "Enlace inválido", description: "Este enlace no es válido o ya fue utilizado." },
  missing_code: { variant: "error", title: "Enlace inválido", description: "El proveedor no devolvió un código de acceso válido." },
  oauth_failed: { variant: "error", title: "No pudimos iniciar sesión", description: "El acceso con Google no está disponible en este momento." },
  rate_limited: { variant: "warning", title: "Demasiados intentos", description: "Esperá unos minutos antes de volver a intentarlo." },
  recovery_link_expired: { variant: "error", title: "El enlace venció", description: "Solicitá un nuevo enlace para restablecer tu contraseña." },
  recovery_link_invalid: { variant: "error", title: "Enlace inválido", description: "Este enlace no es válido o ya fue utilizado." },
  invitation_link_invalid: { variant: "error", title: "Invitación vencida", description: "Solicitá una nueva invitación para configurar tu cuenta." },
  organization_setup_completed: { variant: "success", title: "Configuración completada. Tu espacio de trabajo ya está listo." },
};

const variantStyles: Record<ToastVariant, string> = {
  success: "border-success/35 text-success",
  error: "border-danger/35 text-danger",
  warning: "border-warning/40 text-warning",
  info: "border-accent/35 text-accent",
};

const variantIcons = { success: CheckCircle2, error: CircleAlert, warning: TriangleAlert, info: Info } satisfies Record<ToastVariant, typeof Info>;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const nextId = useRef(0);
  const timers = useRef(new Map<number, number>());

  const removeToast = useCallback((id: number) => {
    const timer = timers.current.get(id);
    if (timer) window.clearTimeout(timer);
    timers.current.delete(id);
    setToasts((current) => current.filter((item) => item.id !== id));
  }, []);

  const dismissToast = useCallback((id: number) => {
    const timer = timers.current.get(id);
    if (timer) window.clearTimeout(timer);
    setToasts((current) => current.map((item) => item.id === id ? { ...item, exiting: true } : item));
    timers.current.set(id, window.setTimeout(() => removeToast(id), EXIT_DURATION));
  }, [removeToast]);

  const toast = useCallback((options: ToastOptions) => {
    const id = ++nextId.current;
    const duration = options.duration ?? DEFAULT_DURATION;
    setToasts((current) => [...current, { id, title: options.title, description: options.description, variant: options.variant ?? "info", duration, exiting: false }]);
    timers.current.set(id, window.setTimeout(() => dismissToast(id), duration));
    return id;
  }, [dismissToast]);

  useEffect(() => {
    const url = new URL(window.location.href);
    const feedbackKey = url.searchParams.get("auth") ?? url.searchParams.get("error") ?? url.searchParams.get("setup");
    if (!feedbackKey) return;
    const feedback = queryFeedback[feedbackKey] ?? { variant: "error" as const, title: "No pudimos completar la operación", description: "Intentá nuevamente en unos minutos." };
    url.searchParams.delete("auth");
    url.searchParams.delete("error");
    url.searchParams.delete("setup");
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}${url.hash}`);
    toast(feedback);
  }, [toast]);

  const value = useMemo(() => ({ toast, dismissToast }), [dismissToast, toast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="pointer-events-none fixed inset-x-3 top-3 z-[100] grid gap-2 sm:left-auto sm:right-4 sm:top-4 sm:w-[min(92vw,390px)]">
        {toasts.map((item) => {
          const Icon = variantIcons[item.variant];
          return (
            <div aria-atomic="true" className={cn("nodo-toast pointer-events-auto relative flex items-start gap-3 overflow-hidden rounded-xl border bg-surface-raised p-4 shadow-[0_18px_50px_rgb(var(--shadow-color)/22%)]", variantStyles[item.variant], item.exiting && "nodo-toast-exit")} key={item.id} role={item.variant === "error" ? "alert" : "status"} style={{ "--toast-duration": `${item.duration}ms` } as CSSProperties}>
              <span className="mt-0.5 grid size-8 shrink-0 place-items-center rounded-lg bg-current/10"><Icon className="size-[18px]" /></span>
              <div className="min-w-0 flex-1 text-ink"><p className="text-sm font-bold leading-5">{item.title}</p>{item.description ? <p className="mt-1 text-sm leading-5 text-ink-secondary">{item.description}</p> : null}</div>
              <button aria-label="Cerrar notificación" className="rounded-md p-1 text-ink-muted transition-colors hover:bg-surface-soft hover:text-ink" onClick={() => dismissToast(item.id)} type="button"><X className="size-4" /></button>
              <span aria-hidden="true" className="nodo-toast-progress absolute inset-x-0 bottom-0 h-0.5 bg-current/70" />
            </div>
          );
        })}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast debe utilizarse dentro de ToastProvider.");
  return context;
}
