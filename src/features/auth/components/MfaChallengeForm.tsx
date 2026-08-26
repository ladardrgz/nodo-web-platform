"use client";

import { ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";

import { Button } from "@/components/ui/Button";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

export function MfaChallengeForm({ destination }: { destination: string }) {
  const [factorId, setFactorId] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void createSupabaseBrowserClient().auth.mfa.listFactors().then((result: { data: { totp: Array<{ id: string; status: string }> } | null; error: unknown }) => {
      const { data, error: factorError } = result;
      const factor = data?.totp.find((item: { id: string; status: string }) => item.status === "verified");
      if (factorError || !factor) setError("No encontramos un segundo factor verificado para esta cuenta.");
      else setFactorId(factor.id);
      setLoading(false);
    });
  }, []);

  const verify = async () => {
    if (!factorId || !/^\d{6}$/.test(code)) { setError("Ingresá un código válido de 6 dígitos."); return; }
    setBusy(true);
    setError(null);
    const { error: verifyError } = await createSupabaseBrowserClient().auth.mfa.challengeAndVerify({ factorId, code });
    if (verifyError) { setError("El código no es válido o venció. Intentá nuevamente."); setBusy(false); return; }
    window.location.assign(destination);
  };

  return <div className="w-full max-w-md rounded-2xl border border-line bg-surface-raised p-6 shadow-sm"><span className="grid size-12 place-items-center rounded-xl bg-accent-soft text-accent"><ShieldCheck className="size-6" /></span><h1 className="mt-5 text-2xl font-bold text-ink">Verificá tu acceso</h1><p className="mt-2 text-sm leading-6 text-ink-secondary">Ingresá el código temporal de tu aplicación autenticadora para acceder al área SUPERADMIN.</p>{error ? <p className="mt-4 rounded-lg bg-danger-soft px-3 py-2 text-sm text-danger" role="alert">{error}</p> : null}<label className="mt-5 block space-y-2"><span className="text-sm font-semibold text-ink">Código de 6 dígitos</span><input autoComplete="one-time-code" className="field-control tracking-[0.3em]" disabled={loading || !factorId} inputMode="numeric" maxLength={6} onChange={(event) => setCode(event.target.value.replace(/\D/g, ""))} value={code} /></label><Button className="mt-5 w-full" disabled={loading || !factorId} loading={busy} loadingText="Verificando…" onClick={verify}>Continuar</Button></div>;
}
