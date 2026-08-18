import Image from "next/image";

import { brand } from "@/config/brand";
import { cn } from "@/lib/cn";

export function AppLogo({ compact = false, className }: { compact?: boolean; className?: string }) {
  return (
    <div className={cn("flex items-center gap-3", className)}>
      <span className={cn("logo-surface grid place-items-center overflow-hidden rounded-xl", compact ? "size-10" : "size-12")}>
        <Image alt={`Logo de ${brand.shortName}`} className={cn("object-contain", compact ? "size-9" : "size-11")} height={48} priority src={brand.assets.logo} width={48} />
      </span>
      <span><strong className="block text-lg text-inherit">{brand.shortName}</strong><span className="block text-xs text-inherit/70">{brand.subtitle}</span></span>
    </div>
  );
}
