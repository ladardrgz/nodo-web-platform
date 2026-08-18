"use client";

import { Menu, X } from "lucide-react";
import Link from "next/link";
import { useState } from "react";

import { AppLogo } from "@/components/branding/AppLogo";
import { ButtonLink } from "@/components/ui/Button";
import { ThemeToggle } from "@/components/ui/ThemeToggle";

const navigation = [
  ["Inicio", "#inicio"], ["¿Qué es Nodo?", "#que-es-nodo"], ["¿Cómo funciona?", "#como-funciona"], ["¿Por qué Nodo?", "#por-que-nodo"], ["Sobre la aplicación", "#sobre-la-aplicacion"], ["Contáctame", "#contactame"],
] as const;

export function PublicNavbar() {
  const [open, setOpen] = useState(false);
  return (
    <header className="sticky top-0 z-30 border-b border-line bg-surface/90 backdrop-blur">
      <div className="public-container flex min-h-18 items-center justify-between gap-4">
        <Link aria-label="Nodo, ir al inicio" href="/" onClick={() => setOpen(false)}><AppLogo compact className="text-primary" /></Link>
        <nav aria-label="Navegación principal" className="hidden items-center gap-5 xl:flex">
          {navigation.map(([label, href]) => <a className="text-sm font-medium text-ink-secondary transition-colors hover:text-ink" href={href} key={href}>{label}</a>)}
        </nav>
        <div className="hidden items-center gap-2 sm:flex"><ThemeToggle /><ButtonLink href="/login" size="sm" variant="secondary">Iniciar sesión</ButtonLink><ButtonLink href="/register" size="sm">Crear cuenta</ButtonLink></div>
        <div className="flex items-center xl:hidden"><span className="sm:hidden"><ThemeToggle /></span><button aria-controls="public-navigation" aria-expanded={open} aria-label={open ? "Cerrar menú" : "Abrir menú"} className="grid size-11 place-items-center rounded-lg text-ink hover:bg-surface-soft" onClick={() => setOpen((value) => !value)} type="button">{open ? <X /> : <Menu />}</button></div>
      </div>
      {open ? <nav className="border-t border-line bg-surface px-4 py-4 shadow-lg xl:hidden" id="public-navigation"><div className="public-container grid gap-1">{navigation.map(([label, href]) => <a className="rounded-lg px-3 py-2.5 text-sm font-semibold text-ink hover:bg-surface-soft" href={href} key={href} onClick={() => setOpen(false)}>{label}</a>)}<div className="mt-3 grid grid-cols-2 gap-2 border-t border-line pt-3"><ButtonLink className="w-full" href="/login" size="sm" variant="secondary">Ingresar</ButtonLink><ButtonLink className="w-full" href="/register" size="sm">Crear cuenta</ButtonLink></div></div></nav> : null}
    </header>
  );
}
