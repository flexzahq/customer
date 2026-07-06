const SESSION_PREFIX = "flexza_patient_";

export type PatientSession = {
  mobile: string;
  name: string;
  doctorCode: string;
  loggedInAt: string;
};

function sessionKey(doctorCode: string): string {
  return `${SESSION_PREFIX}${doctorCode.toUpperCase()}`;
}

export function loadPatientSession(doctorCode: string): PatientSession | null {
  try {
    const raw = localStorage.getItem(sessionKey(doctorCode));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as PatientSession;
    if (!parsed.mobile || parsed.doctorCode?.toUpperCase() !== doctorCode.toUpperCase()) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export function savePatientSession(session: PatientSession): void {
  localStorage.setItem(
    sessionKey(session.doctorCode),
    JSON.stringify({
      ...session,
      doctorCode: session.doctorCode.toUpperCase(),
      loggedInAt: session.loggedInAt || new Date().toISOString(),
    }),
  );
}

export function clearPatientSession(doctorCode: string): void {
  localStorage.removeItem(sessionKey(doctorCode));
}
