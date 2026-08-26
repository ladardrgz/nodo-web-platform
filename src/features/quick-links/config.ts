export const QUICK_LINK_SERVICES = ["GOOGLE", "GMAIL", "YOUTUBE", "WHATSAPP", "FACEBOOK", "INSTAGRAM", "TELEGRAM"] as const;
export type QuickLinkService = (typeof QUICK_LINK_SERVICES)[number];

export const QUICK_LINK_CONFIG: Record<
  QuickLinkService,
  { label: string; hosts: readonly string[]; example: string }
> = {
  GOOGLE: { label: "Google", hosts: ["google.com"], example: "https://www.google.com/" },
  GMAIL: { label: "Gmail", hosts: ["mail.google.com"], example: "https://mail.google.com/mail/u/0/#inbox" },
  YOUTUBE: { label: "YouTube", hosts: ["youtube.com", "youtu.be"], example: "https://www.youtube.com/" },
  WHATSAPP: { label: "WhatsApp", hosts: ["wa.me", "whatsapp.com"], example: "https://web.whatsapp.com/" },
  FACEBOOK: { label: "Facebook", hosts: ["facebook.com"], example: "https://www.facebook.com/" },
  INSTAGRAM: { label: "Instagram", hosts: ["instagram.com"], example: "https://www.instagram.com/" },
  TELEGRAM: { label: "Telegram", hosts: ["t.me", "telegram.me"], example: "https://t.me/tu_usuario" },
};

export interface QuickLinkItem { id?: string; service: QuickLinkService; url: string; enabled: boolean }
