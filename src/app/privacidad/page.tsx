import type { Metadata } from "next";

import { LegalPage, LegalSection } from "@/components/public/LegalPage";

export const metadata: Metadata = { title: "Política de privacidad", description: "Información inicial y editable sobre privacidad en Nodo.", alternates: { canonical: "/privacidad" } };

export default function PrivacyPage() { return <LegalPage title="Política de privacidad" description="Este contenido es una estructura inicial, editable y pendiente de una política definitiva antes de una publicación pública."><LegalSection title="Datos tratados"><p>Nodo puede procesar datos de acceso y la información necesaria para gestionar reparaciones, clientes y dispositivos dentro de las organizaciones que usan la plataforma.</p></LegalSection><LegalSection title="Finalidad"><p>Los datos se utilizan para brindar autenticación, organización y seguimiento de las reparaciones. No se publican datos de contacto de la autora sin su confirmación.</p></LegalSection><LegalSection title="Seguridad y consultas"><p>La plataforma aplica controles de autenticación y acceso por roles. Los canales definitivos para consultas de privacidad se incorporarán cuando estén publicados en la sección de contacto.</p></LegalSection></LegalPage>; }
