import { supabase } from "@/lib/supabase";
import { normalizeDoctorCode } from "@/lib/doctorCode";

export type PatientVisit = {
  tokenId: string;
  tokenNumber: number;
  status: string;
  bookedAt: string;
  completedAt: string | null;
  sessionDate: string;
};

export type PatientActiveToken = {
  tokenId: string;
  tokenNumber: number;
  status: string;
  bookedAt: string;
  sessionDate: string;
};

export type PatientDashboard = {
  loggedIn: boolean;
  patientName: string | null;
  activeToken: PatientActiveToken | null;
  tokensBookedToday: number;
  maxTokensPerDay: number;
  canBook: boolean;
  history: PatientVisit[];
};

export async function fetchPatientDashboard(
  doctorCode: string,
  mobile: string,
): Promise<PatientDashboard> {
  const { data, error } = await supabase.rpc("get_patient_dashboard", {
    p_doctor_code: normalizeDoctorCode(doctorCode),
    p_mobile: mobile,
  });

  if (error) throw error;

  const row = data as {
    ok?: boolean;
    logged_in?: boolean;
    patient_name?: string | null;
    active_token?: {
      token_id?: string;
      token_number?: number;
      status?: string;
      booked_at?: string;
      session_date?: string;
    } | null;
    tokens_booked_today?: number;
    max_tokens_per_day?: number;
    can_book?: boolean;
    history?: Array<{
      token_id?: string;
      token_number?: number;
      status?: string;
      booked_at?: string;
      completed_at?: string | null;
      session_date?: string;
    }>;
  };

  const history = (row.history ?? []).map((h) => ({
    tokenId: h.token_id ?? "",
    tokenNumber: h.token_number ?? 0,
    status: h.status ?? "waiting",
    bookedAt: h.booked_at ?? "",
    completedAt: h.completed_at ?? null,
    sessionDate: h.session_date ?? "",
  }));

  const active = row.active_token;
  return {
    loggedIn: Boolean(row.logged_in),
    patientName: row.patient_name ?? null,
    activeToken: active?.token_number != null
      ? {
          tokenId: active.token_id ?? "",
          tokenNumber: active.token_number,
          status: active.status ?? "waiting",
          bookedAt: active.booked_at ?? "",
          sessionDate: active.session_date ?? "",
        }
      : null,
    tokensBookedToday: row.tokens_booked_today ?? 0,
    maxTokensPerDay: row.max_tokens_per_day ?? 3,
    canBook: Boolean(row.can_book),
    history,
  };
}
