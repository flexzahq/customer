import { supabase } from "@/lib/supabase";
import {
  isValidDoctorCode,
  normalizeDoctorCode,
} from "@/lib/doctorCode";

export type LiveQueue = {
  clinic: {
    id: string;
    name: string;
    slug: string;
    subtitle: string | null;
  } | null;
  doctor: { id: string; name: string; code: string } | null;
  session: { id: string; status: string } | null;
  currentToken: number | null;
  nextTokens: number[];
  waitingCount: number;
  estimatedTime: string;
  hasQueue: boolean;
  hasDoctor: boolean;
};

export type ResolvedDoctor = {
  doctorId: string;
  doctorCode: string;
  doctorName: string;
  clinicId: string;
  clinicName: string;
  clinicSlug: string;
  clinicSubtitle: string | null;
  clinicPhone: string | null;
  clinicEmail: string | null;
  clinicAddress: string | null;
  clinicAbout: string | null;
  morningStart: string | null;
  morningEnd: string | null;
  eveningStart: string | null;
  eveningEnd: string | null;
  minutesPerPatient: number;
  maxTokensPerDay: number;
};

/** Entry screen: resolve unique doctor code → clinic + doctor. */
export async function resolveDoctorCode(
  rawCode: string,
): Promise<ResolvedDoctor | null> {
  const code = normalizeDoctorCode(rawCode);
  if (!isValidDoctorCode(code)) return null;

  const { data, error } = await supabase.rpc("resolve_doctor_code", {
    p_code: code,
  });

  if (error) throw error;

  const row = data as {
    ok?: boolean;
    doctor_id?: string;
    doctor_code?: string;
    doctor_name?: string;
    clinic_id?: string;
    clinic_name?: string;
    clinic_slug?: string;
    clinic_subtitle?: string | null;
    clinic_phone?: string | null;
    clinic_email?: string | null;
    clinic_address?: string | null;
    clinic_about?: string | null;
    morning_start?: string | null;
    morning_end?: string | null;
    evening_start?: string | null;
    evening_end?: string | null;
    minutes_per_patient?: number;
    max_tokens_per_day?: number;
  } | null;

  if (!row?.ok || !row.doctor_code) return null;

  return {
    doctorId: row.doctor_id!,
    doctorCode: row.doctor_code,
    doctorName: row.doctor_name!,
    clinicId: row.clinic_id!,
    clinicName: row.clinic_name!,
    clinicSlug: row.clinic_slug!,
    clinicSubtitle: row.clinic_subtitle ?? null,
    clinicPhone: row.clinic_phone ?? null,
    clinicEmail: row.clinic_email ?? null,
    clinicAddress: row.clinic_address ?? null,
    clinicAbout: row.clinic_about ?? null,
    morningStart: row.morning_start ?? null,
    morningEnd: row.morning_end ?? null,
    eveningStart: row.evening_start ?? null,
    eveningEnd: row.evening_end ?? null,
    minutesPerPatient: row.minutes_per_patient ?? 10,
    maxTokensPerDay: row.max_tokens_per_day ?? 3,
  };
}

import { fetchPublicQueue } from "@/lib/publicQueue";

/** @deprecated Use fetchPublicQueue */
export async function fetchLiveQueueByDoctorCode(
  doctorCode: string,
): Promise<LiveQueue> {
  const q = await fetchPublicQueue(doctorCode);
  return {
    clinic: q.clinic
      ? {
          id: q.clinic.clinicId,
          name: q.clinic.clinicName,
          slug: q.clinic.clinicSlug,
          subtitle: q.clinic.clinicSubtitle,
        }
      : null,
    doctor: q.doctor,
    session: q.session,
    currentToken: q.currentToken,
    nextTokens: q.waitingTokens,
    waitingCount: q.waitingCount,
    estimatedTime: q.estimatedTime,
    hasQueue: q.hasQueue,
    hasDoctor: q.hasDoctor,
  };
}
