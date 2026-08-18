import {
  BadgeDollarSign,
  Boxes,
  LayoutDashboard,
  Smartphone,
  Users,
} from "lucide-react";

export const adminNavigation = [
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
