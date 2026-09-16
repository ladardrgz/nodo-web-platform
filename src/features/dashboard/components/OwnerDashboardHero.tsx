import Image from "next/image";
import Link from "next/link";

import styles from "./OwnerDashboardHero.module.css";

interface OwnerDashboardHeroProps {
  firstName: string;
  greeting: string;
  logoUrl: string | null;
  organizationName: string;
  showPrimaryAction: boolean;
}

export function OwnerDashboardHero({
  firstName,
  greeting,
  logoUrl,
  organizationName,
  showPrimaryAction,
}: OwnerDashboardHeroProps) {
  const initials =
    organizationName
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0])
      .join("")
      .toUpperCase() || "N";

  return (
    <section className="relative isolate overflow-hidden rounded-2xl border border-app-border bg-app-card px-5 py-5 shadow-[0_8px_30px_rgb(var(--shadow-color)/7%)] sm:px-6 sm:py-6 lg:px-7">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 -z-20"
      >
        <Image
          alt=""
          className="object-cover object-center opacity-20 dark:opacity-25"
          fill
          priority
          sizes="100vw"
          src="/images/img_container_admin.png"
        />

        <div className="absolute inset-0 bg-app-card/75" />

        <div className="absolute inset-0 bg-gradient-to-r from-app-card via-app-card/90 to-app-card/55" />
      </div>

      <div className="relative flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex min-w-0 flex-1 items-center gap-4 sm:gap-5">
          <div className="relative grid size-16 shrink-0 place-items-center overflow-hidden rounded-xl border border-app-border bg-app-surface-soft text-lg font-bold text-accent shadow-sm sm:size-20">
            {logoUrl ? (
              <Image
                alt={`Logo de ${organizationName}`}
                className="object-contain p-2"
                fill
                priority
                sizes="80px"
                src={logoUrl}
                unoptimized
              />
            ) : (
              <span aria-label={`Iniciales de ${organizationName}`}>
                {initials}
              </span>
            )}
          </div>

          <div className="min-w-0">
            <p className="text-xs font-bold uppercase tracking-[0.16em] text-accent">
              Inicio operativo
            </p>

            <h1 className="mt-1.5 text-xl font-bold tracking-tight text-app-text sm:text-2xl">
              {greeting}, {firstName}
            </h1>

            <p className="mt-1 text-sm text-app-text-secondary sm:text-base">
              Esto está pasando hoy en{" "}
              <strong className="font-bold text-app-text">
                {organizationName}
              </strong>
              .
            </p>
          </div>
        </div>

        {showPrimaryAction ? (
          <div className="w-full shrink-0 sm:w-auto">
            <Link
              href="/repairs/new"
              className={styles.continueApplication}
              aria-label="Nueva reparación"
            >
              <span
                className={styles.iconArea}
                aria-hidden="true"
              >
                <span className={styles.pencil} />

                <span className={styles.folder}>
                  <span className={styles.folderTop}>
                    <svg viewBox="0 0 24 27">
                      <path d="M1,0 L23,0 C23.5522847,-1.01453063e-16 24,0.44771525 24,1 L24,8.17157288 C24,8.70200585 23.7892863,9.21071368 23.4142136,9.58578644 L20.5857864,12.4142136 C20.2107137,12.7892863 20,13.2979941 20,13.8284271 L20,26 C20,26.5522847 19.5522847,27 19,27 L1,27 C0.44771525,27 6.76353751e-17,26.5522847 0,26 L0,1 C-6.76353751e-17,0.44771525 0.44771525,1.01453063e-16 1,0 Z" />
                    </svg>
                  </span>

                  <span className={styles.paper} />
                </span>
              </span>

              <span>Nueva reparación</span>
            </Link>
          </div>
        ) : null}
      </div>
    </section>
  );
}