/** Normalize user input to doctor code (A–Z, 0–9, 4–12 chars). */
export function normalizeDoctorCode(raw: string): string {
  return raw.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
}

/**
 * Extract doctor code from:
 * - plain code: "AB12CD"
 * - path: /d/AB12CD
 * - full URL: https://app.flexza.in/d/AB12CD?...
 */
export function extractDoctorCode(input: string): string | null {
  const trimmed = input.trim();
  if (!trimmed) return null;

  try {
    const url = new URL(trimmed);
    const fromPath = url.pathname.match(/\/d\/([A-Za-z0-9]{4,12})/i);
    if (fromPath?.[1]) return normalizeDoctorCode(fromPath[1]);
    const q = url.searchParams.get("code") ?? url.searchParams.get("doctor");
    if (q) return normalizeDoctorCode(q);
  } catch {
    // not a URL
  }

  const pathMatch = trimmed.match(/\/d\/([A-Za-z0-9]{4,12})/i);
  if (pathMatch?.[1]) return normalizeDoctorCode(pathMatch[1]);

  const code = normalizeDoctorCode(trimmed);
  if (code.length >= 4 && code.length <= 12) return code;
  return null;
}

export function isValidDoctorCode(code: string): boolean {
  return /^[A-Z0-9]{4,12}$/.test(code);
}

export function doctorQueuePath(code: string): string {
  return `/d/${normalizeDoctorCode(code)}`;
}

/** Permanent patient entry URL for QR (never rotate daily). */
export function patientQueueUrl(code: string, origin?: string): string {
  const base =
    origin ??
    (typeof window !== "undefined" ? window.location.origin : "");
  return `${base}${doctorQueuePath(code)}`;
}
