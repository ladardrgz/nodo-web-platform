import Link from "next/link";
import type { ButtonHTMLAttributes, ReactNode } from "react";

import { NodoLoader } from "@/components/ui/NodoLoader";
import { cn } from "@/lib/cn";

type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
type ButtonSize = "sm" | "md" | "lg";

const variantClasses: Record<ButtonVariant, string> = {
  primary:
    "bg-accent-button text-white shadow-sm hover:bg-accent-button-hover active:bg-accent-button-active focus-visible:outline-accent",
  secondary:
    "bg-surface text-ink ring-1 ring-inset ring-line hover:bg-surface-soft active:bg-line",
  ghost: "text-ink-secondary hover:bg-surface-soft hover:text-ink active:bg-line",
  danger: "bg-danger-button text-white hover:bg-danger-button-hover active:bg-danger-button-hover focus-visible:outline-danger",
};

const sizeClasses: Record<ButtonSize, string> = {
  sm: "min-h-9 px-3 text-sm",
  md: "min-h-11 px-4 text-sm",
  lg: "min-h-12 px-5 text-base",
};

function buttonClasses(
  variant: ButtonVariant,
  size: ButtonSize,
  className?: string,
): string {
  return cn(
    "inline-flex items-center justify-center gap-2 rounded-lg font-semibold transition-[color,background-color,box-shadow,transform] focus-visible:outline-2 focus-visible:outline-offset-2 active:translate-y-px disabled:pointer-events-none disabled:translate-y-0 disabled:opacity-50",
    variantClasses[variant],
    sizeClasses[size],
    className,
  );
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  loadingText?: string;
}

export function Button({
  className,
  variant = "primary",
  size = "md",
  type = "button",
  loading = false,
  loadingText,
  children,
  disabled,
  ...props
}: ButtonProps) {
  return (
    <button
      aria-busy={loading || undefined}
      className={buttonClasses(variant, size, className)}
      disabled={disabled || loading}
      type={type}
      {...props}
    >
      {loading ? <NodoLoader size="sm" /> : null}
      {loading ? loadingText ?? children : children}
    </button>
  );
}

interface ButtonLinkProps {
  href: string;
  children: ReactNode;
  variant?: ButtonVariant;
  size?: ButtonSize;
  className?: string;
}

export function ButtonLink({
  href,
  children,
  variant = "primary",
  size = "md",
  className,
}: ButtonLinkProps) {
  return (
    <Link href={href} className={buttonClasses(variant, size, className)}>
      {children}
    </Link>
  );
}
