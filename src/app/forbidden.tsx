import { ShieldX } from "lucide-react";
import Link from "next/link";

export default function Forbidden() {
  return <main className="grid min-h-screen place-items-center bg-background px-4"><div className="max-w-md text-center"><span className="mx-auto grid size-16 place-items-center rounded-full bg-red-50 text-danger"><ShieldX className="size-7" /></span><p className="mt-6 text-xs font-bold uppercase tracking-[0.18em] text-danger">403</p><h1 className="mt-2 text-2xl font-bold text-primary">No tenés permiso</h1><p className="mt-3 text-sm leading-6 text-muted">Tu sesión es válida, pero tu rol no permite acceder a esta sección.</p><Link className="mt-6 inline-flex min-h-11 items-center rounded-lg bg-accent px-5 text-sm font-semibold text-white" href="/">Volver a mi inicio</Link></div></main>;
}
