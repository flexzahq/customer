import { supabase } from "@/lib/supabase";
import { normalizeDoctorCode } from "@/lib/doctorCode";

export type StaffTokenRow = {
  id: string;
  number: number;
  status: string;
  booked_at: string;
  completed_at?: string | null;
  patient_name: string | null;
  patient_mobile: string;
};

export type StaffQueue = {
  doctorId: string;
  doctorCode: string;
  doctorName: string;
  clinicName: string;
  clinicSubtitle: string | null;
  sessionId: string | null;
  sessionStatus: "open" | "paused" | "closed" | null;
  serving: StaffTokenRow | null;
  waiting: StaffTokenRow[];
  skipped: StaffTokenRow[];
  completed: StaffTokenRow[];
  waitingCount: number;
  totalToday: number;
};

function mapToken(row: Record<string, unknown> | null): StaffTokenRow | null {
  if (!row) return null;
  return {
    id: String(row.id),
    number: Number(row.number),
    status: String(row.status),
    booked_at: String(row.booked_at),
    completed_at: row.completed_at ? String(row.completed_at) : null,
    patient_name: (row.patient_name as string | null) ?? null,
    patient_mobile: String(row.patient_mobile ?? ""),
  };
}

function mapTokenList(value: unknown): StaffTokenRow[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((row) => mapToken(row as Record<string, unknown>))
    .filter((row): row is StaffTokenRow => row != null);
}

export async function fetchStaffQueue(doctorCode: string): Promise<StaffQueue> {
  const { data, error } = await supabase.rpc("get_staff_queue", {
    p_doctor_code: normalizeDoctorCode(doctorCode),
  });

  if (error) throw error;

  const row = data as Record<string, unknown>;
  return {
    doctorId: String(row.doctor_id ?? ""),
    doctorCode: String(row.doctor_code ?? ""),
    doctorName: String(row.doctor_name ?? ""),
    clinicName: String(row.clinic_name ?? ""),
    clinicSubtitle: (row.clinic_subtitle as string | null) ?? null,
    sessionId: row.session_id ? String(row.session_id) : null,
    sessionStatus: (row.session_status as StaffQueue["sessionStatus"]) ?? null,
    serving: mapToken(row.serving as Record<string, unknown> | null),
    waiting: mapTokenList(row.waiting),
    skipped: mapTokenList(row.skipped),
    completed: mapTokenList(row.completed),
    waitingCount: Number(row.waiting_count ?? 0),
    totalToday: Number(row.total_today ?? 0),
  };
}

export async function openTodaySession(doctorId: string): Promise<string> {
  const { data, error } = await supabase.rpc("open_today_session", {
    p_doctor_id: doctorId,
  });
  if (error) throw error;
  const row = data as { session_id?: string };
  if (!row.session_id) throw new Error("session_open_failed");
  return row.session_id;
}

export async function setSessionStatus(
  sessionId: string,
  status: "open" | "paused" | "closed",
): Promise<void> {
  const { error } = await supabase.rpc("set_session_status", {
    p_session_id: sessionId,
    p_status: status,
  });
  if (error) throw error;
}

export async function completeToken(sessionId: string): Promise<void> {
  const { error } = await supabase.rpc("complete_token", {
    p_session_id: sessionId,
  });
  if (error) throw error;
}

export async function skipToken(sessionId: string): Promise<void> {
  const { error } = await supabase.rpc("skip_token", {
    p_session_id: sessionId,
  });
  if (error) throw error;
}

export function initialsFromName(name: string | null, mobile: string): string {
  if (name?.trim()) {
    const parts = name.trim().split(/\s+/);
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
    }
    return name.slice(0, 2).toUpperCase();
  }
  return mobile.slice(-2);
}

export function formatTokenTime(iso: string): string {
  try {
    return new Intl.DateTimeFormat("en-IN", {
      day: "2-digit",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
      timeZone: "Asia/Kolkata",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}
