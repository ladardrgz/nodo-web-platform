"use client";

import { RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";

export default function RepairsError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <Card className="mx-auto max-w-2xl p-6 text-center sm:p-8"><h1 className="text-xl font-bold text-primary">No pudimos cargar las reparaciones</h1><p className="mt-2 text-sm leading-6 text-muted">Tus registros permanecen guardados. Intentá cargar nuevamente el listado.</p><Button className="mt-5" onClick={reset}><RotateCcw className="size-4" />Reintentar</Button></Card>;
}
