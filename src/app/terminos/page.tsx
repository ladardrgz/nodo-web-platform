import type { Metadata } from "next";

import { LegalPage, LegalSection } from "@/components/public/LegalPage";

export const metadata: Metadata = { title: "Términos y condiciones", description: "Información inicial y editable sobre el uso de Nodo.", alternates: { canonical: "/terminos" } };

export default function TermsPage() { return <LegalPage title="Términos y condiciones" description="Este contenido es una estructura inicial, editable y pendiente de revisión jurídica antes de una publicación definitiva."><LegalSection title="Uso de Nodo"><p>Nodo es una plataforma gratuita orientada a ordenar la gestión de reparaciones y su seguimiento. Las personas usuarias deben utilizarla de forma lícita y responsable.</p></LegalSection><LegalSection title="Información registrada"><p>Cada organización es responsable de la información que carga y de verificar la exactitud de sus procesos, diagnósticos, presupuestos y comunicaciones con sus clientes.</p></LegalSection><LegalSection title="Cambios futuros"><p>Estas condiciones podrán actualizarse cuando el proyecto evolucione. La versión vigente se publicará en esta misma página.</p></LegalSection></LegalPage>; }
