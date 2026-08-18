import type { ReactNode } from "react";

import { PublicAuthHeader } from "@/components/public/PublicAuthHeader";

export function AuthPageFrame({ children }: { children: ReactNode }) { return <div className="public-shell min-h-screen"><PublicAuthHeader /><main className="flex min-h-[calc(100vh-4rem)] items-center justify-center px-4 py-2 sm:px-6 sm:py-3">{children}</main></div>; }
