import { supabase } from "@/lib/supabase";
import {
  isValidDoctorCode,
  normalizeDoctorCode,
} from "@/lib/doctorCode";

const MINUTES_PER_TOKEN = 10;

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
};

function todayInKolkata(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
  }).format(new Date());
}

function formatEta(minutes: number): string {
  if (minutes <= 0) return "0m";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

function blankQueue(): LiveQueue {
  return {
    clinic: null,
    doctor: null,
    session: null,
    currentToken: null,
    nextTokens: [],
    waitingCount: 0,
    estimatedTime: "0m",
    hasQueue: false,
    hasDoctor: false,
  };
}

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
  };
}

/** Live queue for one doctor (unique code). */
export async function fetchLiveQueueByDoctorCode(
  doctorCode: string,
): Promise<LiveQueue> {
  const code = normalizeDoctorCode(doctorCode);
  if (!isValidDoctorCode(code)) return blankQueue();

  const resolved = await resolveDoctorCode(code);
  if (!resolved) return blankQueue();

  const clinic = {
    id: resolved.clinicId,
    name: resolved.clinicName,
    slug: resolved.clinicSlug,
    subtitle: resolved.clinicSubtitle,
  };

  const doctor = {
    id: resolved.doctorId,
    name: resolved.doctorName,
    code: resolved.doctorCode,
  };

  const { data: session, error: sessionError } = await supabase
    .from("queue_sessions")
    .select("id, status")
    .eq("doctor_id", doctor.id)
    .eq("session_date", todayInKolkata())
    .maybeSingle();

  if (sessionError) throw sessionError;
  if (!session) {
    return {
      clinic,
      doctor,
      session: null,
      currentToken: null,
      nextTokens: [],
      waitingCount: 0,
      estimatedTime: "0m",
      hasQueue: false,
      hasDoctor: true,
    };
  }

  const { data: tokens, error: tokensError } = await supabase
    .from("tokens")
    .select("number, status")
    .eq("session_id", session.id)
    .in("status", ["waiting", "serving"])
    .order("number", { ascending: true });

  if (tokensError) throw tokensError;

  const list = tokens ?? [];
  const serving = list.find((t) => t.status === "serving");
  const waiting = list.filter((t) => t.status === "waiting");
  const waitingCount = waiting.length;

  return {
    clinic,
    doctor,
    session,
    currentToken: serving?.number ?? null,
    nextTokens: waiting.slice(0, 2).map((t) => t.number),
    waitingCount,
    estimatedTime: formatEta(waitingCount * MINUTES_PER_TOKEN),
    hasQueue: Boolean(serving) || waitingCount > 0,
    hasDoctor: true,
  };
}
