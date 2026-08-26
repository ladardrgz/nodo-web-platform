"use client";

import { QrCode, ShieldCheck, ShieldOff, X } from "lucide-react";
import Image from "next/image";
import { useCallback, useEffect, useState } from "react";

import { useToast } from "@/components/feedback/ToastProvider";
import { Button } from "@/components/ui/Button";
import { ContextHelp } from "@/features/superadmin/components/ContextHelp";
import { recordSuperadminSecurityEventAction } from "@/features/superadmin/security-actions";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

type Factor = { id: string; status: string; friendly_name?: string };
type Enrollment = { factorId: string; qrCode: string };

export function MfaSecurity() {
  const { toast } = useToast();
  const [factor, setFactor] = useState<Factor | null>(null);
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null);
  const [code, setCode] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [disableOpen, setDisableOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadFactor = useCallback(async () => {
    const { data, error: loadError } = await createSupabaseBrowserClient().auth.mfa.listFactors();
    if (loadError) {
      setError("No pudimos consultar la autenticación en dos pasos.");
    } else {
      setFactor(data.totp.find((item: Factor) => item.status === "verified") ?? null);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    let active = true;
    void createSupabaseBrowserClient().auth.mfa.listFactors().then((result: { data: { totp: Factor[] } | null; error: unknown }) => {
      if (!active) return;
      const { data, error: loadError } = result;
      if (loadError) setError("No pudimos consultar la autenticación en dos pasos.");
      else setFactor(data?.totp.find((item: Factor) => item.status === "verified") ?? null);
      setLoading(false);
    });
    return () => { active = false; };
  }, []);
  useEffect(() => {
    if (!disableOpen) return;
    const close = (event: KeyboardEvent) => { if (event.key === "Escape") setDisableOpen(false); };
    document.addEventListener("keydown", close);
    return () => document.removeEventListener("keydown", close);
  }, [disableOpen]);

  const startEnrollment = async () => {
    setBusy(true);
    setError(null);
    const { data, error: enrollError } = await createSupabaseBrowserClient().auth.mfa.enroll({ factorType: "totp", friendlyName: "Nodo SUPERADMIN" });
    if (enrollError) {
      setError("No pudimos iniciar la configuración. Intentá nuevamente.");
    } else {
      setEnrollment({ factorId: data.id, qrCode: data.totp.qr_code });
      await recordSuperadminSecurityEventAction("MFA_ENROLL_STARTED");
    }
    setBusy(false);
  };

  const cancelEnrollment = async () => {
    if (enrollment) await createSupabaseBrowserClient().auth.mfa.unenroll({ factorId: enrollment.factorId });
    setEnrollment(null);
    setCode("");
    setError(null);
  };

  const verifyEnrollment = async () => {
    if (!enrollment || !/^\d{6}$/.test(code)) {
      setError("Ingresá el código de 6 dígitos de tu aplicación autenticadora.");
      return;
    }
    setBusy(true);
    setError(null);
    const { error: verifyError } = await createSupabaseBrowserClient().auth.mfa.challengeAndVerify({ factorId: enrollment.factorId, code });
    if (verifyError) {
      setError("El código no es válido o venció. Generá uno nuevo e intentá otra vez.");
    } else {
      await recordSuperadminSecurityEventAction("MFA_ENABLED");
      setEnrollment(null);
      setCode("");
      await loadFactor();
      toast({ variant: "success", title: "Autenticación en dos pasos activada." });
    }
    setBusy(false);
  };

  const disable = async () => {
    if (!factor || confirmation !== "DESACTIVAR MFA") return;
    setBusy(true);
    setError(null);
    const { error: disableError } = await createSupabaseBrowserClient().auth.mfa.unenroll({ factorId: factor.id });
    if (disableError) {
      setError("No pudimos desactivar la autenticación en dos pasos. Volvé a verificar tu sesión e intentá nuevamente.");
    } else {
      await recordSuperadminSecurityEventAction("MFA_DISABLED");
      setFactor(null);
      setDisableOpen(false);
      setConfirmation("");
      toast({ variant: "success", title: "Autenticación en dos pasos desactivada." });
    }
    setBusy(false);
  };

  return (
    <section className="rounded-xl border border-line bg-surface-raised p-5 sm:p-6">
      <div className="flex items-start justify-between gap-4"><div className="flex items-start gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><ShieldCheck className="size-5" /></span><div><div className="flex items-center gap-2"><h2 className="font-bold text-ink">Autenticación en dos pasos</h2><ContextHelp label="Ayuda sobre autenticación en dos pasos" title="¿Cómo protege el MFA tu cuenta?">Supabase Auth verifica un código temporal generado por tu aplicación autenticadora. Nodo no guarda el secreto ni genera criptografía propia.</ContextHelp></div><p className="mt-1 text-sm text-ink-muted">Protección TOTP oficial de Supabase Auth para tu acceso global.</p></div></div><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${factor ? "bg-success-soft text-success" : enrollment ? "bg-warning-soft text-warning" : "bg-surface-soft text-ink-secondary"}`}>{loading ? "Verificando" : factor ? "Activado" : enrollment ? "Configurando" : "No configurado"}</span></div>
      {error ? <p className="mt-4 rounded-lg bg-danger-soft px-3 py-2 text-sm text-danger" role="alert">{error}</p> : null}
      {!loading && !factor && !enrollment ? <Button className="mt-5" loading={busy} loadingText="Preparando…" onClick={startEnrollment}><QrCode className="size-4" />Configurar</Button> : null}
      {enrollment ? <div className="mt-5 grid gap-5 border-t border-line pt-5 sm:grid-cols-[180px_minmax(0,1fr)]"><div className="rounded-xl bg-white p-3"><Image alt="Código QR para configurar el autenticador de Nodo" className="h-auto w-full" height={156} src={enrollment.qrCode} unoptimized width={156} /></div><div><h3 className="font-bold text-ink">Escaneá el código QR</h3><p className="mt-2 text-sm leading-6 text-ink-secondary">Abrí tu aplicación autenticadora, escaneá el código e ingresá el código temporal de 6 dígitos.</p><label className="mt-4 block space-y-2"><span className="text-sm font-semibold text-ink">Código de verificación</span><input autoComplete="one-time-code" className="field-control max-w-56 tracking-[0.3em]" inputMode="numeric" maxLength={6} onChange={(event) => setCode(event.target.value.replace(/\D/g, ""))} value={code} /></label><div className="mt-4 flex flex-wrap gap-2"><Button disabled={busy} onClick={() => void cancelEnrollment()} variant="secondary">Cancelar</Button><Button loading={busy} loadingText="Verificando…" onClick={verifyEnrollment}>Verificar y activar</Button></div></div></div> : null}
      {factor ? <div className="mt-5 flex flex-wrap items-center justify-between gap-4 rounded-lg bg-surface-soft p-4"><div><p className="font-semibold text-ink">Segundo factor verificado</p><p className="mt-1 text-xs text-ink-muted">Las rutas SUPERADMIN exigen nivel AAL2 cuando este factor está activo.</p></div><Button onClick={() => setDisableOpen(true)} variant="danger"><ShieldOff className="size-4" />Desactivar MFA</Button></div> : null}
      {disableOpen ? <div className="fixed inset-0 z-[80] flex items-start justify-center overflow-y-auto bg-brand-surface/35 px-4 py-20 backdrop-blur-sm" onPointerDown={(event) => { if (event.currentTarget === event.target) setDisableOpen(false); }}><div aria-modal="true" className="w-full max-w-md rounded-xl border border-line bg-surface-raised p-5 shadow-[0_24px_80px_rgb(var(--shadow-color)/28%)]" role="dialog"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold text-ink">Desactivar autenticación en dos pasos</h3><p className="mt-2 text-sm leading-6 text-ink-secondary">Esta acción reduce la protección de tu cuenta global. Escribí <strong>DESACTIVAR MFA</strong> exactamente para continuar.</p></div><button aria-label="Cerrar" className="grid size-8 place-items-center rounded-lg text-ink-muted hover:bg-surface-soft" onClick={() => setDisableOpen(false)}><X className="size-4" /></button></div><input autoComplete="off" className="field-control mt-5" onChange={(event) => setConfirmation(event.target.value)} value={confirmation} /><div className="mt-5 flex justify-end gap-2"><Button disabled={busy} onClick={() => setDisableOpen(false)} variant="secondary">Cancelar</Button><Button disabled={confirmation !== "DESACTIVAR MFA"} loading={busy} loadingText="Desactivando…" onClick={disable} variant="danger">Confirmar desactivación</Button></div></div></div> : null}
    </section>
  );
}
