"use client";

import Image from "next/image";
import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import type { DynamicDeviceSection } from "@/features/repairs/reception/types";

const columnVariants = { 1: "grid-cols-1", 2: "grid-cols-1 md:grid-cols-2" } as const;
const gapVariants = { sm: "gap-3", md: "gap-5", lg: "gap-7" } as const;
const containerVariants = { section: "", "repeatable-section": "[&>div]:grid-cols-1" } as const;
const sectionImages: Record<string, string> = {
  processor: "/images/processor.png",
  memory: "/images/ram.png",
  graphics: "/images/gpu.png",
  storage: "/images/storage.png",
  display: "/images/display.png",
  power: "/images/battery.png",
  operating_system: "/images/operating-system.png",
  connectivity: "/images/connectivity.png",
  ports: "/images/ports.png",
  accessories: "/images/accessories.png",
  keyboard: "/images/keyboard.png",
  touchpad: "/images/touchpad.png",
  webcam: "/images/webcam.png",
  audio: "/images/audio.png",
  motherboard: "/images/motherboard.png",
  cooling: "/images/cooling.png",
  power_supply: "/images/power-supply.png",
  network_adapter: "/images/network-adapter.png",
};

function sectionImage(key: string) {
  const suffix = key.replace(/^(notebook|desktop|pc)_/, "");
  return sectionImages[suffix];
}

export function DeviceFormSection({ section, children }: { section: DynamicDeviceSection; children: ReactNode }) {
  const columns = section.uiConfig.columns?.md === 2 ? 2 : 1;
  const gap = section.uiConfig.gap ?? "md";
  const container = section.uiConfig.container ?? "section";
  const image = sectionImage(section.key);
  return (
    <section aria-labelledby={`section-${section.id}`} className={cn("border-t border-border pt-6", containerVariants[container])}>
      <div className="flex items-start gap-3">
        {image ? <span className="grid size-11 shrink-0 place-items-center rounded-lg border border-line bg-white p-2 shadow-sm"><Image alt="" aria-hidden className="size-full object-contain" height={512} src={image} width={512} /></span> : null}
        <div>
          <h3 className="text-base font-bold text-primary" id={`section-${section.id}`}>{section.title}</h3>
          {section.description ? <p className="mt-1 text-sm text-muted">{section.description}</p> : null}
        </div>
      </div>
      <div className={cn("mt-4 grid", columnVariants[columns], gapVariants[gap])}>{children}</div>
    </section>
  );
}
