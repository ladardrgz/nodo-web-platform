import type { Metadata } from "next";
import type { ReactNode } from "react";

import { ToastProvider } from "@/components/feedback/ToastProvider";
import { ThemeProvider } from "@/components/feedback/ThemeProvider";
import { brand } from "@/config/brand";
import { getAppUrl } from "@/lib/supabase/config";

import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(getAppUrl()),
  title: {
    default: "Nodo | Home",
    template: `${brand.shortName} | %s`,
  },
  description: "Nodo es una aplicación gratuita para gestionar órdenes, diagnósticos, aprobaciones, reparaciones y seguimiento de dispositivos de servicios técnicos.",
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    locale: "es_AR",
    siteName: brand.name,
    title: "Nodo | Plataforma web para gestionar reparaciones",
    description: "Gestioná reparaciones con trazabilidad, claridad y confianza.",
  },
  twitter: { card: "summary", title: "Nodo | Plataforma web para gestionar reparaciones", description: "Gestioná reparaciones con trazabilidad, claridad y confianza." },
  icons: { icon: "/images/img_logo_nodo_p_icon.ico", shortcut: "/images/img_logo_nodo_p_icon.ico" },
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  const themeScript = `(function(){try{var saved=localStorage.getItem('nodo-theme');var theme=saved==='dark'||saved==='light'?saved:(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');document.documentElement.dataset.theme=theme;document.documentElement.style.colorScheme=theme;}catch(e){document.documentElement.dataset.theme='light';document.documentElement.style.colorScheme='light';}})();`;
  return (
    <html lang="es-AR" suppressHydrationWarning>
      <head><script dangerouslySetInnerHTML={{ __html: themeScript }} /></head>
      <body><ThemeProvider><ToastProvider>{children}</ToastProvider></ThemeProvider></body>
    </html>
  );
}
