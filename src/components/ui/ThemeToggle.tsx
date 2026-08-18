"use client";

import { Moon, Sun } from "lucide-react";
import { useSyncExternalStore } from "react";

const themeEvent = "nodo-theme-change";

function subscribe(callback: () => void) {
  window.addEventListener(themeEvent, callback);
  return () => window.removeEventListener(themeEvent, callback);
}

function getThemeSnapshot() { return document.documentElement.dataset.theme === "dark"; }
function getServerSnapshot() { return false; }

export function ThemeToggle({ className = "" }: { className?: string }) {
  const isDark = useSyncExternalStore(subscribe, getThemeSnapshot, getServerSnapshot);
  function toggleTheme() {
    const nextTheme = document.documentElement.dataset.theme !== "dark";
    document.documentElement.dataset.theme = nextTheme ? "dark" : "light";
    document.documentElement.style.colorScheme = nextTheme ? "dark" : "light";
    window.localStorage.setItem("nodo-theme", nextTheme ? "dark" : "light");
    window.dispatchEvent(new Event(themeEvent));
  }
  return <button aria-label={isDark ? "Activar modo claro" : "Activar modo oscuro"} aria-pressed={isDark} className={`rounded-full p-1 focus-visible:outline-accent ${className}`} onClick={toggleTheme} type="button"><span aria-hidden className="theme-switch-track block"><span className="theme-switch-thumb">{isDark ? <Moon className="size-3.5" /> : <Sun className="size-3.5" />}</span></span></button>;
}
