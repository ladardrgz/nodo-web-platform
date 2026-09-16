import {
  Activity,
  BadgeDollarSign,
  Boxes,
  Building2,
  Gauge,
  LayoutDashboard,
  Settings,
  Smartphone,
  TableProperties,
  UserCircle2,
  Users,
} from "lucide-react";

import type { AppRole } from "@/types/auth";

export interface NavigationItem {
  href: string;
  label: string;
  icon: typeof LayoutDashboard;
}

const ownerNavigation: readonly NavigationItem[] = [
  {
    href: "/dashboard",
    label: "Dashboard",
    icon: LayoutDashboard,
  },
  {
    href: "/repairs",
    label: "Reparaciones",
    icon: Smartphone,
  },
  {
    href: "/customers",
    label: "Clientes",
    icon: Users,
  },
  {
    href: "/inventory",
    label: "Inventario",
    icon: Boxes,
  },
  {
    href: "/prices",
    label: "Precios",
    icon: BadgeDollarSign,
  },
] as const;

const superadminNavigation: readonly NavigationItem[] = [
  { href: "/superadmin#overview", label: "Resumen", icon: Gauge },
  { href: "/superadmin#organizations", label: "Organizaciones", icon: Building2 },
  { href: "/superadmin#users", label: "Usuarios", icon: Users },
  { href: "/superadmin/master", label: "Catálogos maestros", icon: TableProperties },
  { href: "/superadmin/activity", label: "Actividad", icon: Activity },
  { href: "/superadmin#system", label: "Estado del sistema", icon: Settings },
  { href: "/superadmin/profile", label: "Mi perfil", icon: UserCircle2 },
];

const customerNavigation: readonly NavigationItem[] = [
  { href: "/portal", label: "Mi seguimiento", icon: Smartphone },
];

export const adminNavigation = ownerNavigation;

export function getNavigationForRole(role: AppRole): readonly NavigationItem[] {
  if (role === "SUPERADMIN") return superadminNavigation;
  if (role === "CUSTOMER") return customerNavigation;
  return ownerNavigation;
}

export function getRoleDashboardHref(role: AppRole): string {
  if (role === "SUPERADMIN") return "/superadmin";
  if (role === "CUSTOMER") return "/portal";
  return "/dashboard";
}

export function getRoleNavigationLabel(role: AppRole): string {
  if (role === "SUPERADMIN") return "Administración global";
  if (role === "CUSTOMER") return "Mi cuenta";
  return "Operación";
}
