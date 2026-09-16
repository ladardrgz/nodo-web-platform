export function nameError(value: string, field: "nombre" | "apellido") {
  const clean = value.trim().replace(/\s+/g, " ");
  if (!clean) return `Ingresá el ${field}.`;
  if (clean.length < 2) return `El ${field} debe tener al menos 2 caracteres.`;
  if (clean.length > 80) return `El ${field} no puede superar los 80 caracteres.`;
  if (!/^[\p{L}\p{M}]+(?:[.'’-]?[\p{L}\p{M}]+)*(?:\s+[\p{L}\p{M}]+(?:[.'’-]?[\p{L}\p{M}]+)*)*$/u.test(clean)) return `El ${field} contiene caracteres no válidos.`;
  return undefined;
}

export function customerPhoneError(value: string) {
  const clean = value.replace(/\D/g, "");
  if (!clean) return "Ingresá el número de teléfono.";
  return clean.length === 10 ? undefined : "El número de teléfono debe contener 10 dígitos.";
}

export function emailError(value: string) {
  const clean = value.trim().toLowerCase();
  if (!clean) return undefined;
  if (clean.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(clean)) return "Ingresá un correo electrónico válido.";
  const [, domain] = clean.split("@");
  if (!domain) return "Ingresá un correo electrónico válido.";
  const typos: Record<string, string> = { "gamil.com": "gmail.com", "gmial.com": "gmail.com", "gmail.con": "gmail.com", "gmail.co": "gmail.com", "gmail.comj": "gmail.com", "gmail.comm": "gmail.com", "hotmal.com": "hotmail.com", "hotmai.com": "hotmail.com", "hotmail.con": "hotmail.com", "hotmail.comj": "hotmail.com", "outlok.com": "outlook.com", "outllok.com": "outlook.com", "outlook.con": "outlook.com", "outlook.comj": "outlook.com", "yaho.com": "yahoo.com", "yahoo.con": "yahoo.com", "yahoo.comj": "yahoo.com", "icloud.con": "icloud.com", "icloud.comj": "icloud.com", "protonmal.com": "protonmail.com", "protonmai.com": "protonmail.com", "protonmail.con": "protonmail.com", "proton.m": "proton.me" };
  if (typos[domain]) return `¿Quisiste escribir @${typos[domain]}?`;
  const providers = ["gmail", "outlook", "hotmail", "live", "yahoo", "icloud", "proton", "protonmail", "aol", "zoho", "gmx", "yandex"];
  const valid = ["gmail.com", "outlook.com", "hotmail.com", "live.com", "yahoo.com", "icloud.com", "proton.me", "protonmail.com", "aol.com", "zoho.com", "gmx.com", "yandex.com"];
  return providers.some((provider) => domain.startsWith(provider)) && !valid.includes(domain) ? "El dominio del correo electrónico no parece válido." : undefined;
}
