import { ChevronLeft, ChevronRight } from "lucide-react";

import { cn } from "@/lib/cn";

export function Pagination({ page, pageSize, totalItems, onPageChange }: { page: number; pageSize: number; totalItems: number; onPageChange: (page: number) => void }) {
  const totalPages = Math.max(1, Math.ceil(totalItems / pageSize));
  if (totalItems <= pageSize) return null;
  const pages = Array.from({ length: totalPages }, (_, index) => index + 1).filter((candidate) => Math.abs(candidate - page) <= 2 || candidate === 1 || candidate === totalPages);

  return <nav aria-label="Paginación" className="flex flex-wrap items-center justify-between gap-3"><p className="text-xs font-semibold text-muted">Página {page} de {totalPages}</p><div className="flex items-center gap-1"><button aria-label="Página anterior" className="grid size-9 place-items-center rounded-lg border border-border bg-white text-primary disabled:opacity-40" disabled={page <= 1} onClick={() => onPageChange(page - 1)} type="button"><ChevronLeft className="size-4" /></button>{pages.map((candidate, index) => <span className="contents" key={candidate}>{index > 0 && candidate - pages[index - 1] > 1 ? <span className="px-1 text-muted">…</span> : null}<button aria-current={candidate === page ? "page" : undefined} className={cn("size-9 rounded-lg text-sm font-semibold", candidate === page ? "bg-accent text-white" : "border border-border bg-white text-primary hover:bg-slate-50")} onClick={() => onPageChange(candidate)} type="button">{candidate}</button></span>)}<button aria-label="Página siguiente" className="grid size-9 place-items-center rounded-lg border border-border bg-white text-primary disabled:opacity-40" disabled={page >= totalPages} onClick={() => onPageChange(page + 1)} type="button"><ChevronRight className="size-4" /></button></div></nav>;
}
