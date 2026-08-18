import { ArrowLeft } from "lucide-react";
import Link from "next/link";

import { AppLogo } from "@/components/branding/AppLogo";
import { ThemeToggle } from "@/components/ui/ThemeToggle";

export function PublicAuthHeader() { return <header className="public-container flex min-h-16 items-center justify-between"><Link aria-label="Nodo, ir al inicio" href="/"><AppLogo compact className="text-ink" /></Link><div className="flex items-center gap-1"><ThemeToggle /><Link className="inline-flex min-h-10 items-center gap-2 rounded-lg px-3 text-sm font-semibold text-ink-secondary transition-colors hover:bg-surface hover:text-ink" href="/"><ArrowLeft className="size-4" />Volver al inicio</Link></div></header>; }
