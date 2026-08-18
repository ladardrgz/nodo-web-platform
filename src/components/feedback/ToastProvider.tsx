"use client";

import { CheckCircle2, CircleAlert, X } from "lucide-react";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

import { cn } from "@/lib/cn";

type ToastTone = "success" | "error";
interface ToastItem { id: number; message: string; tone: ToastTone }
interface ToastContextValue { showToast: (message: string, tone?: ToastTone) => void }

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const showToast = useCallback((message: string, tone: ToastTone = "success") => {
    const id = Date.now() + Math.random();
    setToasts((current) => [...current, { id, message, tone }]);
    window.setTimeout(() => setToasts((current) => current.filter((toast) => toast.id !== id)), 5000);
  }, []);
  const value = useMemo(() => ({ showToast }), [showToast]);

  useEffect(() => {
    const url = new URL(window.location.href);
    const feedback = url.searchParams.get("auth");
    const messages: Record<string, { message: string; tone: ToastTone }> = {
      session_started: { message: "Sesión iniciada correctamente.", tone: "success" },
      password_changed: { message: "Contraseña actualizada correctamente.", tone: "success" },
      signed_out: { message: "Sesión cerrada correctamente.", tone: "success" },
      session_expired: { message: "Tu sesión expiró. Volvé a iniciar sesión.", tone: "error" },
    };
    const toast = feedback ? messages[feedback] : undefined;
    if (!toast) return;

    url.searchParams.delete("auth");
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}${url.hash}`);
    const timeoutId = window.setTimeout(() => showToast(toast.message, toast.tone), 0);
    return () => window.clearTimeout(timeoutId);
  }, [showToast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div aria-live="polite" className="fixed right-4 top-4 z-[100] grid w-[min(92vw,380px)] gap-2">
        {toasts.map((toast) => {
          const Icon = toast.tone === "success" ? CheckCircle2 : CircleAlert;
          return <div className={cn("flex items-start gap-3 rounded-xl border bg-white p-4 text-sm shadow-xl", toast.tone === "success" ? "border-emerald-200 text-emerald-900" : "border-red-200 text-red-900")} key={toast.id}><Icon className="mt-0.5 size-5 shrink-0" /><p className="flex-1 leading-5">{toast.message}</p><button aria-label="Cerrar aviso" className="rounded p-1 hover:bg-slate-100" onClick={() => setToasts((current) => current.filter((item) => item.id !== toast.id))} type="button"><X className="size-4" /></button></div>;
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
