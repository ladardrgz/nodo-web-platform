import { NodoLoader } from "@/components/ui/NodoLoader";

export default function Loading() {
  return (
    <div className="grid min-h-[40vh] place-items-center" role="status">
      <div className="flex flex-col items-center gap-3 text-accent">
        <NodoLoader label="Cargando Nodo" size="lg" />
        <p className="text-sm font-semibold text-ink-secondary">Conectando la información…</p>
      </div>
    </div>
  );
}
