import { SearchX } from "lucide-react";

import { ButtonLink } from "@/components/ui/Button";

export default function NotFoundPage() {
  return <main className="grid min-h-screen place-items-center bg-background px-4"><div className="max-w-md text-center"><span className="mx-auto grid size-16 place-items-center rounded-full bg-slate-100 text-muted"><SearchX className="size-7" /></span><p className="mt-6 text-xs font-bold uppercase tracking-[0.18em] text-accent">404</p><h1 className="mt-2 text-2xl font-bold text-primary">No encontramos esta página</h1><p className="mt-3 text-sm leading-6 text-muted">La orden, el cliente o la ruta solicitada no existe en los datos disponibles.</p><div className="mt-6"><ButtonLink href="/dashboard">Volver al dashboard</ButtonLink></div></div></main>;
}
