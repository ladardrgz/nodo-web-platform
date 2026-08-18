import type { ReactNode } from "react";

import { PublicFooter } from "@/components/public/PublicFooter";
import { PublicNavbar } from "@/components/public/PublicNavbar";

export function LegalPage({ title, description, children }: { title: string; description: string; children: ReactNode }) {
  return <div className="public-shell min-h-screen"><PublicNavbar /><main className="public-container py-14 sm:py-20"><article className="mx-auto max-w-3xl rounded-[1.25rem] border border-line bg-surface-raised p-6 shadow-[0_16px_45px_rgb(var(--shadow-color)/8%)] sm:p-10"><p className="section-kicker">Información del sitio</p><h1 className="mt-3 text-3xl font-bold tracking-tight text-ink sm:text-4xl">{title}</h1><p className="mt-5 text-base leading-7 text-ink-secondary">{description}</p><div className="mt-10 space-y-8 text-sm leading-7 text-ink-secondary">{children}</div></article></main><PublicFooter /></div>;
}

export function LegalSection({ title, children }: { title: string; children: ReactNode }) { return <section><h2 className="text-lg font-bold text-ink">{title}</h2><div className="mt-2">{children}</div></section>; }
