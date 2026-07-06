import { useQuery } from "@tanstack/react-query";
import { resolveDoctorCode, type ResolvedDoctor } from "@/lib/queue";
import { normalizeDoctorCode } from "@/lib/doctorCode";

export type ClinicProfile = ResolvedDoctor;

export function formatTimeRange(
  start: string | null | undefined,
  end: string | null | undefined,
): string | null {
  if (!start || !end) return null;
  return `${formatTimeDisplay(start)} – ${formatTimeDisplay(end)}`;
}

export function formatTimeDisplay(value: string): string {
  const part = String(value).slice(0, 5);
  const [hs, ms] = part.split(":");
  let h = Number(hs);
  const m = Number(ms);
  if (Number.isNaN(h) || Number.isNaN(m)) return part;
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12 || 12;
  return `${h}:${String(m).padStart(2, "0")} ${ampm}`;
}

export function useClinicProfile(doctorCodeRaw: string) {
  const doctorCode = normalizeDoctorCode(doctorCodeRaw);
  return useQuery({
    queryKey: ["clinic-profile", doctorCode],
    queryFn: () => resolveDoctorCode(doctorCode),
    enabled: doctorCode.length >= 4,
    staleTime: 30_000,
  });
}
