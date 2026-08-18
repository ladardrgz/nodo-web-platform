"use client";

import { Check, ClipboardCheck, FileSearch, PackageCheck, Pause, Play, Wrench } from "lucide-react";
import { useEffect, useState } from "react";

const stages = ["Ingreso", "Diagnóstico", "Presupuesto", "Aprobación", "Reparación", "Entrega"];

const scenes = [
  { eyebrow: "Nueva orden", title: "Recepción del dispositivo", icon: ClipboardCheck, body: <div className="grid gap-3 sm:grid-cols-2"><DemoField label="Cliente" value="María López" /><DemoField label="Equipo" value="Samsung Galaxy S23" /><DemoField className="sm:col-span-2" label="Motivo" value="No enciende" /></div>, action: "Crear orden" },
  { eyebrow: "Orden #NST-00231", title: "Dispositivo recibido", icon: Check, body: <DemoNotice text="La recepción quedó registrada con el estado y las observaciones iniciales." />, action: "Continuar al diagnóstico" },
  { eyebrow: "Diagnóstico", title: "Batería sin tensión adecuada", icon: FileSearch, body: <DemoNotice text="Se revisaron alimentación, conector y respuesta de la batería. Se propone reemplazo sujeto a aprobación." />, action: "Guardar diagnóstico" },
  { eyebrow: "Presupuesto", title: "$85.000 · Reemplazo de batería", icon: ClipboardCheck, body: <DemoNotice text="La propuesta y el gasto quedan visibles antes de continuar." />, action: "Enviar para aprobación" },
  { eyebrow: "Aprobación registrada", title: "La reparación puede comenzar", icon: Check, body: <DemoNotice text="La decisión del cliente queda vinculada a la orden." />, action: "Iniciar reparación" },
  { eyebrow: "En reparación", title: "Trabajo técnico en curso", icon: Wrench, body: <DemoNotice text="El estado se actualiza según el ritmo real de trabajo y la disponibilidad del repuesto." />, action: "Marcar como reparado" },
  { eyebrow: "Listo para entregar", title: "Reparación finalizada", icon: PackageCheck, body: <DemoNotice text="La orden conserva diagnóstico, aprobación, intervención y resultado final." />, action: "Registrar entrega" },
] as const;

export function RepairFlowDemo() {
  const [active, setActive] = useState(scenes.length - 1);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    if (paused || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const timer = window.setInterval(() => setActive((current) => current === scenes.length - 1 ? 0 : current + 1), 2200);
    return () => window.clearInterval(timer);
  }, [paused]);

  const scene = scenes[active];
  const SceneIcon = scene.icon;
  const stageIndex = Math.min(active, stages.length - 1);

  return <div className="rounded-[1.4rem] border border-line bg-surface-raised p-4 shadow-[0_18px_50px_rgb(var(--shadow-color)/14%)] sm:p-6"><div className="flex items-center justify-between gap-4 border-b border-line pb-4"><div><p className="text-xs font-bold uppercase tracking-[0.14em] text-accent">Demostración de una reparación</p><p className="mt-1 text-sm text-ink-secondary">Una orden avanza sin perder su contexto.</p></div><button aria-label={paused ? "Reanudar demostración" : "Pausar demostración"} className="grid size-10 shrink-0 place-items-center rounded-lg border border-line bg-surface-soft text-ink-secondary hover:border-accent hover:text-accent" onClick={() => setPaused((value) => !value)} type="button">{paused ? <Play className="size-4" /> : <Pause className="size-4" />}</button></div><ol aria-label="Etapas de la reparación" className="mt-5 flex items-start justify-between gap-1">{stages.map((stage, index) => <li className="relative flex min-w-0 flex-1 flex-col items-center text-center" key={stage}><button aria-label={`Mostrar etapa ${stage}`} className="relative z-10 grid size-7 place-items-center rounded-full border text-[10px] font-bold transition-colors" onClick={() => { setActive(index); setPaused(true); }} style={{ background: index <= stageIndex ? "var(--accent)" : "var(--bg-surface-soft)", borderColor: index <= stageIndex ? "var(--accent)" : "var(--border-strong)", color: index <= stageIndex ? "white" : "var(--text-muted)" }} type="button">{index < stageIndex ? <Check className="size-3.5" /> : index + 1}</button>{index < stages.length - 1 ? <span aria-hidden className="absolute left-1/2 top-3 h-px w-full" style={{ background: index < stageIndex ? "var(--accent)" : "var(--border)" }} /> : null}<span className="mt-2 hidden truncate text-[10px] font-semibold text-ink-muted sm:block">{stage}</span></li>)}</ol><div aria-live="polite" className="mt-5 min-h-[270px] rounded-xl border border-line bg-surface-soft p-5 sm:p-6"><div className="flex items-start gap-3"><span className="grid size-10 shrink-0 place-items-center rounded-lg bg-accent-soft text-accent"><SceneIcon className="size-5" /></span><div><p className="text-xs font-bold uppercase tracking-[0.14em] text-accent">{scene.eyebrow}</p><h3 className="mt-1 text-xl font-bold text-ink">{scene.title}</h3></div></div><div className="mt-5 text-sm text-ink-secondary">{scene.body}</div><div className="mt-5 flex justify-end"><span className="inline-flex min-h-10 items-center rounded-lg bg-accent px-4 text-sm font-bold text-white">{scene.action}</span></div></div></div>;
}

function DemoField({ label, value, className = "" }: { label: string; value: string; className?: string }) { return <div className={className}><span className="block text-xs font-semibold text-ink-muted">{label}</span><span className="mt-1 block rounded-lg border border-line bg-surface px-3 py-2.5 font-semibold text-ink">{value}</span></div>; }
function DemoNotice({ text }: { text: string }) { return <p className="rounded-lg border border-line bg-surface px-4 py-3 leading-6">{text}</p>; }
