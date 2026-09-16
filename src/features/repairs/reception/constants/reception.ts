export const WIZARD_STEPS = ["Cliente", "Dispositivo", "Recepción", "Confirmación"] as const;
export const MAX_RECEPTION_PHOTO_SIZE = 5 * 1024 * 1024;
export const RECEPTION_PHOTO_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
