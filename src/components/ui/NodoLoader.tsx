import { cn } from "@/lib/cn";

type NodoLoaderSize = "sm" | "md" | "lg";

const sizeClasses: Record<NodoLoaderSize, string> = {
  sm: "h-4 w-7",
  md: "h-6 w-11",
  lg: "h-10 w-[4.5rem]",
};

export function NodoLoader({
  size = "md",
  label,
  className,
}: {
  size?: NodoLoaderSize;
  label?: string;
  className?: string;
}) {
  return (
    <span
      aria-hidden={label ? undefined : true}
      aria-label={label}
      className={cn("nodo-loader inline-flex shrink-0 items-center justify-center", sizeClasses[size], className)}
      role={label ? "status" : undefined}
    >
      <svg aria-hidden="true" className="size-full overflow-visible" viewBox="0 0 48 24">
        <path className="nodo-loader-track" d="M2 13h10l4-7 7 15 7-17 5 9h11" pathLength="100" />
        <path className="nodo-loader-pulse" d="M2 13h10l4-7 7 15 7-17 5 9h11" pathLength="100" />
      </svg>
      {label ? <span className="sr-only">{label}</span> : null}
    </span>
  );
}
