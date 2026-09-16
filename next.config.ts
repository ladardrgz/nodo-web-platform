import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  images: {
    localPatterns: [
      {
        pathname: "/images/**",
        search: "",
      },
      {
        pathname: "/images/img_logo_nodo.png",
        search: "?v=20260827-2223",
      },
    ],
  },
  experimental: {
    authInterrupts: true,
    serverActions: {
      bodySizeLimit: "3mb",
    },
  },
};

export default nextConfig;
