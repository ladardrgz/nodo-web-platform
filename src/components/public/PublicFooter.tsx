import { Mail, MessageCircle } from "lucide-react";
import Link from "next/link";

import { AppLogo } from "@/components/branding/AppLogo";
import { GitHubIcon } from "@/components/icons/GitHubIcon";

const externalContact = [[GitHubIcon, "GitHub", "https://github.com/ladardrgz/ladardrgz"], [MessageCircle, "WhatsApp", "https://wa.me/543705176505"], [Mail, "Email", "mailto:ladardrgz@gmail.com"]] as const;

export function PublicFooter() {
  return <footer className="border-t border-line bg-brand-surface text-brand-contrast"><div className="public-container grid gap-10 py-12 sm:grid-cols-2 lg:grid-cols-4"><div><AppLogo className="text-brand-contrast" /><p className="mt-5 text-sm font-bold">Gestión clara de reparaciones.</p><p className="mt-2 max-w-sm text-sm leading-6 text-brand-muted">Información conectada para organizar el trabajo técnico y reducir incertidumbre.</p></div><FooterColumn title="Plataforma" links={[["Inicio", "/"], ["¿Qué es Nodo?", "/#que-es-nodo"], ["¿Cómo funciona?", "/#como-funciona"], ["Crear cuenta", "/register"], ["Iniciar sesión", "/login"]]} /><FooterColumn title="Información" links={[["Sobre la aplicación", "/#sobre-la-aplicacion"], ["Contáctame", "/#contactame"], ["Términos y condiciones", "/terminos"], ["Política de privacidad", "/privacidad"]]} /><div><h2 className="text-sm font-bold">Contacto</h2><ul className="mt-4 space-y-3">{externalContact.map(([Icon, label, href]) => <li key={label}><a className="inline-flex min-h-9 items-center gap-2 text-sm text-brand-muted transition-colors hover:text-white" href={href} rel={href.startsWith("http") ? "noopener noreferrer" : undefined} target={href.startsWith("http") ? "_blank" : undefined}><Icon className="size-4" />{label}</a></li>)}</ul></div></div><div className="border-t border-white/12"><div className="public-container flex min-h-16 flex-wrap items-center justify-between gap-2 text-xs text-brand-subtle"><span>© 2026 <strong className="font-bold text-white">Nodo</strong>.</span><span>Proyecto gratuito y sin fines de lucro.</span></div></div></footer>;
}

function FooterColumn({ title, links }: { title: string; links: [string, string][] }) { return <div><h2 className="text-sm font-bold">{title}</h2><ul className="mt-4 space-y-2.5">{links.map(([label, href]) => <li key={href}><Link className="text-sm text-brand-muted transition-colors hover:text-white" href={href}>{label}</Link></li>)}</ul></div>; }
