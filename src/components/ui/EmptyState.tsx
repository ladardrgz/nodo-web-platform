import Image from "next/image";
import type { ReactNode } from "react";

import { brand } from "@/config/brand";

interface EmptyStateProps {
  title: string;
  description: string;
  action?: ReactNode;
  showIllustration?: boolean;
}

export function EmptyState({
  title,
  description,
  action,
  showIllustration = false,
}: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center px-6 py-12 text-center">
      {showIllustration ? (
        <Image
          alt="Persona consultando el seguimiento de su equipo"
          className="mb-6 size-36 rounded-full object-cover"
          height={144}
          src={brand.assets.emptyCustomerState}
          sizes="144px"
          width={144}
        />
      ) : null}
      <h2 className="text-lg font-bold text-primary">{title}</h2>
      <p className="mt-2 max-w-md text-sm leading-6 text-muted">{description}</p>
      {action ? <div className="mt-5">{action}</div> : null}
    </div>
  );
}
