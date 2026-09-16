import { ArrowLeft } from "lucide-react";
import Link from "next/link";

import { AppLogo } from "@/components/branding/AppLogo";
import { ThemeToggle } from "@/components/ui/ThemeToggle";

export function PublicAuthHeader() { return <header className="public-container flex min-h-16 items-center justify-between gap-2"><Link aria-label="Nodo, ir al inicio" className="min-w-0 shrink" href="/"><AppLogo compact className="text-ink" /></Link><div className="flex shrink-0 items-center gap-1"><ThemeToggle /><Link aria-label="Volver al inicio" className="inline-flex min-h-10 items-center gap-2 rounded-lg px-1 text-sm font-semibold text-ink-secondary transition-colors hover:bg-surface hover:text-ink sm:px-3" href="/"><ArrowLeft className="size-4" /><span className="hidden sm:inline">Volver al inicio</span></Link></div></header>; }
