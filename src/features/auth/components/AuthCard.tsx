import type { ReactNode } from "react";

export function AuthCard({ eyebrow, title, description, children, footer }: { eyebrow: string; title: string; description: ReactNode; children: ReactNode; footer?: ReactNode }) {
  return <div className="w-full max-w-[450px] rounded-[1.25rem] border border-line bg-surface-raised p-5 shadow-[0_16px_45px_rgb(var(--shadow-color)/10%)] sm:p-6"><p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">{eyebrow}</p><h1 className="mt-2 text-2xl font-bold tracking-tight text-ink sm:text-3xl">{title}</h1><p className="mt-2 text-sm leading-6 text-ink-secondary">{description}</p><div className="mt-4">{children}</div>{footer ? <div className="mt-4 border-t border-line pt-4 text-center text-sm text-ink-secondary">{footer}</div> : null}</div>;
}
