import { supabase } from "@/lib/supabase";
import {
  isValidDoctorCode,
  normalizeDoctorCode,
} from "@/lib/doctorCode";
import { resolveDoctorCode, type ResolvedDoctor } from "@/lib/queue";

export type PublicQueue = {
  clinic: ResolvedDoctor | null;
  doctor: { id: string; name: string; code: string } | null;
  session: { id: string; status: string } | null;
  currentToken: number | null;
  waitingTokens: number[];
  waitingCount: number;
  minutesPerPatient: number;
  maxTokensPerDay: number;
  estimatedTime: string;
  hasQueue: boolean;
  hasDoctor: boolean;
};

function formatEta(minutes: number): string {
  if (minutes <= 0) return "0m";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

function blankQueue(): PublicQueue {
  return {
    clinic: null,
    doctor: null,
    session: null,
    currentToken: null,
    waitingTokens: [],
    waitingCount: 0,
    minutesPerPatient: 10,
    maxTokensPerDay: 3,
    estimatedTime: "0m",
    hasQueue: false,
    hasDoctor: false,
  };
}

export function estimateWaitMinutes(
  waitingTokens: number[],
  myTokenNumber: number | null | undefined,
  minutesPerPatient: number,
): number {
  if (myTokenNumber == null) {
    return waitingTokens.length * minutesPerPatient;
  }
  const ahead = waitingTokens.filter((n) => n < myTokenNumber).length;
  return ahead * minutesPerPatient;
}

export async function fetchPublicQueue(doctorCode: string): Promise<PublicQueue> {
  const code = normalizeDoctorCode(doctorCode);
  if (!isValidDoctorCode(code)) return blankQueue();

  const resolved = await resolveDoctorCode(code);
  if (!resolved) return blankQueue();

  const doctor = {
    id: resolved.doctorId,
    name: resolved.doctorName,
    code: resolved.doctorCode,
  };

  const { data, error } = await supabase.rpc("get_public_queue", {
    p_doctor_code: code,
  });

  if (error) throw error;

  const row = data as {
    ok?: boolean;
    session_id?: string | null;
    session_status?: string | null;
    current_token?: number | null;
    waiting_tokens?: number[];
    waiting_count?: number;
    minutes_per_patient?: number;
    max_tokens_per_day?: number;
  };

  const waitingTokens = Array.isArray(row.waiting_tokens)
    ? row.waiting_tokens.map((n) => Number(n))
    : [];
  const waitingCount = row.waiting_count ?? waitingTokens.length;
  const minutesPerPatient = row.minutes_per_patient ?? resolved.minutesPerPatient ?? 10;

  const currentToken = row.current_token ?? null;

  return {
    clinic: resolved,
    doctor,
    session: row.session_id
      ? { id: row.session_id, status: row.session_status ?? "open" }
      : null,
    currentToken,
    waitingTokens,
    waitingCount,
    minutesPerPatient,
    maxTokensPerDay: row.max_tokens_per_day ?? resolved.maxTokensPerDay ?? 3,
    estimatedTime: formatEta(waitingCount * minutesPerPatient),
    hasQueue: Boolean(currentToken) || waitingCount > 0,
    hasDoctor: true,
  };
}
