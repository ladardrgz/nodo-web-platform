"use client";

import { AlertTriangle, RotateCcw } from "lucide-react";
import { useEffect } from "react";

import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";

export default function DashboardError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    console.error("Error técnico del dashboard OWNER:", error.digest ?? error.name);
  }, [error]);

  return (
    <Card className="grid min-h-80 place-items-center p-6 text-center">
      <div className="max-w-md">
        <span className="mx-auto grid size-12 place-items-center rounded-xl bg-danger-soft text-danger"><AlertTriangle aria-hidden="true" className="size-6" /></span>
        <h1 className="mt-4 text-xl font-bold text-app-text">No pudimos cargar el dashboard</h1>
        <p className="mt-2 text-sm leading-6 text-app-text-muted">Intentá nuevamente. Si el problema continúa, cerrá sesión y volvé a ingresar.</p>
        <Button className="mt-5" onClick={retry}><RotateCcw aria-hidden="true" className="size-4" />Intentar nuevamente</Button>
      </div>
    </Card>
  );
}
