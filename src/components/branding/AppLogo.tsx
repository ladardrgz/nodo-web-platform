import Image from "next/image";

import { brand } from "@/config/brand";
import { cn } from "@/lib/cn";

interface AppLogoProps {
  compact?: boolean;
  iconOnly?: boolean;
  showSubtitle?: boolean;
  className?: string;
}

export function AppLogo({
  compact = false,
  iconOnly = false,
  showSubtitle = true,
  className,
}: AppLogoProps) {
  const imageSize = compact ? 36 : 44;

  if (iconOnly) {
    return (
      <div className={cn("flex items-center justify-center", className)}>
        <span className={cn("logo-surface grid place-items-center overflow-hidden rounded-xl", compact ? "size-10" : "size-12")}>
          <Image alt={`Logo de ${brand.shortName}`} className={cn("object-contain", compact ? "size-9" : "size-11")} height={imageSize} priority src={brand.assets.logo} width={imageSize} />
        </span>
      </div>
    );
  }

  return (
    <div className={cn("flex min-w-0 items-center gap-3", className)}>
      <span className={cn("logo-surface grid shrink-0 place-items-center overflow-hidden rounded-xl", compact ? "size-10" : "size-12")}>
        <Image
          alt={`Logo de ${brand.shortName}`}
          className={cn("object-contain", compact ? "size-9" : "size-11")}
          height={imageSize}
          priority
          src={brand.assets.logo}
          width={imageSize}
        />
      </span>

      <span className="min-w-0">
        <strong className="block truncate text-lg text-inherit">{brand.shortName}</strong>
        {showSubtitle ? <span className="block truncate text-xs text-inherit/70">{brand.subtitle}</span> : null}
      </span>
    </div>
  );
}
