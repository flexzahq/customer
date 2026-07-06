import { supabase } from "@/lib/supabase";
import { normalizeDoctorCode } from "@/lib/doctorCode";

export type BookOtpResult = {
  ok: boolean;
  challengeId?: string;
  devOtp?: string;
  expiresInSeconds?: number;
};

export type BookTokenResult = {
  ok: boolean;
  tokenNumber: number;
  status: string;
  sessionId: string;
  doctorCode: string;
  doctorName: string;
};

function rpcErrorMessage(error: { message?: string; details?: string } | null): string {
  const raw = error?.message ?? error?.details ?? "request_failed";
  if (raw.includes("otp_cooldown")) return "otp_cooldown";
  if (raw.includes("otp_rate_limited")) return "otp_rate_limited";
  if (raw.includes("otp_invalid")) return "otp_invalid";
  if (raw.includes("otp_not_found_or_expired")) return "otp_not_found_or_expired";
  if (raw.includes("otp_too_many_attempts")) return "otp_too_many_attempts";
  if (raw.includes("booking_paused")) return "booking_paused";
  if (raw.includes("booking_closed")) return "booking_closed";
  if (raw.includes("already_in_queue")) return "already_in_queue";
  if (raw.includes("doctor_not_found")) return "doctor_not_found";
  if (raw.includes("invalid_mobile")) return "invalid_mobile";
  if (raw.includes("invalid_otp")) return "invalid_otp";
  return "request_failed";
}

export async function requestBookOtp(
  doctorCode: string,
  mobile: string,
): Promise<BookOtpResult> {
  const { data, error } = await supabase.rpc("request_book_otp", {
    p_doctor_code: normalizeDoctorCode(doctorCode),
    p_mobile: mobile,
  });

  if (error) {
    throw new Error(rpcErrorMessage(error));
  }

  const row = data as {
    ok?: boolean;
    challenge_id?: string;
    dev_otp?: string;
    expires_in_seconds?: number;
  };

  return {
    ok: Boolean(row?.ok),
    challengeId: row?.challenge_id,
    devOtp: row?.dev_otp,
    expiresInSeconds: row?.expires_in_seconds,
  };
}

export async function bookToken(params: {
  doctorCode: string;
  mobile: string;
  name: string;
  otpCode: string;
}): Promise<BookTokenResult> {
  const { data, error } = await supabase.rpc("book_token", {
    p_doctor_code: normalizeDoctorCode(params.doctorCode),
    p_mobile: params.mobile,
    p_name: params.name,
    p_otp_code: params.otpCode,
  });

  if (error) {
    throw new Error(rpcErrorMessage(error));
  }

  const row = data as {
    ok?: boolean;
    token_number?: number;
    status?: string;
    session_id?: string;
    doctor_code?: string;
    doctor_name?: string;
  };

  if (!row?.ok || row.token_number == null) {
    throw new Error("request_failed");
  }

  return {
    ok: true,
    tokenNumber: row.token_number,
    status: row.status ?? "waiting",
    sessionId: row.session_id ?? "",
    doctorCode: row.doctor_code ?? "",
    doctorName: row.doctor_name ?? "",
  };
}
