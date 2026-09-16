export const ORGANIZATION_LOGO_MAX_BYTES = 2 * 1024 * 1024;

export const ORGANIZATION_LOGO_EXTENSIONS = {
  "image/avif": "avif",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
} as const;

export type OrganizationLogoMime = keyof typeof ORGANIZATION_LOGO_EXTENSIONS;

function bytesEqual(bytes: Uint8Array, offset: number, expected: readonly number[]): boolean {
  return expected.every((value, index) => bytes[offset + index] === value);
}

function ascii(bytes: Uint8Array, start: number, end: number): string {
  return String.fromCharCode(...bytes.slice(start, end));
}

export function detectOrganizationLogoMime(bytes: Uint8Array): OrganizationLogoMime | null {
  if (bytes.length >= 8 && bytesEqual(bytes, 0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (bytes.length >= 3 && bytesEqual(bytes, 0, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 12) === "WEBP") return "image/webp";
  if (bytes.length >= 16 && ascii(bytes, 4, 8) === "ftyp") {
    const brands = ascii(bytes, 8, Math.min(bytes.length, 32));
    if (brands.includes("avif") || brands.includes("avis")) return "image/avif";
  }
  return null;
}

export function validateOrganizationLogoMetadata(file: Pick<File, "size" | "type"> | null): string | null {
  if (!file || file.size === 0) return null;
  if (!(file.type in ORGANIZATION_LOGO_EXTENSIONS)) return "El formato del logo no es compatible. Usá JPG, PNG, WebP o AVIF.";
  if (file.size > ORGANIZATION_LOGO_MAX_BYTES) return "El logo no puede superar los 2 MB.";
  return null;
}

export async function validateOrganizationLogoFile(file: File): Promise<string | null> {
  const metadataError = validateOrganizationLogoMetadata(file);
  if (metadataError) return metadataError;
  const detected = detectOrganizationLogoMime(new Uint8Array(await file.slice(0, 32).arrayBuffer()));
  if (!detected || detected !== file.type) return "El contenido del archivo no coincide con un formato de imagen permitido.";
  return null;
}
