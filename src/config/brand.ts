export const brand = {
  name: "Nodo",
  shortName: "Nodo",
  subtitle: "Gestión para servicios técnicos",
  tagline: "Trazabilidad clara para cada reparación",
  assets: {
    // Invalida la caché de Next/Image y del navegador cuando se reemplaza el archivo del logo.
    logo: "/images/img_logo_nodo.png?v=20260827-2223",
    banner: "/images/img_banner_nodo.png",
    dashboardBackground: "/images/img_dashboard_admin.png",
    loginBackground: "/images/img_login.png",
    emptyCustomerState: "/images/cliente_sin_dispositivos.jpg",
  },
} as const;
