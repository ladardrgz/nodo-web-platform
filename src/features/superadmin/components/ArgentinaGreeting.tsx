"use client";

import { useEffect, useState } from "react";

import { argentinaGreeting } from "@/lib/argentina-time";

export function ArgentinaGreeting({ name, initialGreeting }: { name: string; initialGreeting: string }) {
  const [greeting, setGreeting] = useState(initialGreeting);
  useEffect(() => {
    const timer = window.setInterval(() => setGreeting(argentinaGreeting()), 60_000);
    return () => window.clearInterval(timer);
  }, []);
  return <>{greeting}, {name}</>;
}
