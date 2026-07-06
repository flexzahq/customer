import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent,
  type ClipboardEvent,
} from "react";
import { Drawer, DrawerContent, DrawerHeader, DrawerTitle } from "@/components/ui/drawer";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Phone, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { useI18n, type TranslationKey } from "@/lib/i18n";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { bookToken, requestBookOtp } from "@/lib/booking";
import { savePatientSession } from "@/lib/patientSession";

interface LoginDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  doctorCode: string;
  initialMobile?: string;
  onLoginSuccess: (token: number) => void;
}

const STEPS = 2;
const STEP_PHONE = 0;
const STEP_OTP = 1;

function StepBar({ current }: { current: number }) {
  return (
    <div className="flex items-center gap-1.5 px-6 pt-5">
      {Array.from({ length: STEPS }).map((_, i) => (
        <div
          key={i}
          className="h-1 flex-1 rounded-full transition-all duration-300"
          style={{
            background: i <= current ? "hsl(var(--primary))" : "hsl(var(--muted))",
          }}
        />
      ))}
    </div>
  );
}

function mapBookingError(code: string, t: (key: TranslationKey) => string): string {
  switch (code) {
    case "otp_invalid":
    case "invalid_otp":
      return t("errOtpInvalid");
    case "otp_not_found_or_expired":
      return t("errOtpExpired");
    case "otp_cooldown":
      return t("errOtpCooldown");
    case "otp_rate_limited":
    case "otp_too_many_attempts":
      return t("errOtpRateLimited");
    case "booking_paused":
      return t("errBookingPaused");
    case "booking_closed":
      return t("errBookingClosed");
    case "clinic_plan_expired":
      return t("errPlanExpired");
    case "doctor_access_expired":
      return t("errPlanExpired");
    case "clinic_disabled":
      return t("errRequestFailed");
    case "already_in_queue":
      return t("errAlreadyInQueue");
    case "patient_name_required":
      return t("errNameRequired");
    case "token_daily_limit_reached":
      return t("errDailyTokenLimit");
    case "doctor_not_found":
      return t("errDoctorNotFound");
    case "booking_unavailable":
      return t("errBookingUnavailable");
    default:
      return t("errRequestFailed");
  }
}

export const LoginDialog = ({
  open,
  onOpenChange,
  doctorCode,
  initialMobile,
  onLoginSuccess,
}: LoginDialogProps) => {
  const [stepIndex, setStepIndex] = useState(STEP_PHONE);
  const [mobile, setMobile] = useState("");
  const [name, setName] = useState("");
  const [otpDigits, setOtpDigits] = useState<string[]>(["", "", "", ""]);
  const [devOtp, setDevOtp] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const mobileInputRef = useRef<HTMLInputElement>(null);
  const nameInputRef = useRef<HTMLInputElement>(null);
  const otpRefs = useRef<Array<HTMLInputElement | null>>([]);
  const attemptedOtpRef = useRef<string | null>(null);
  const allowCloseRef = useRef(false);
  const { t } = useI18n();

  const reset = () => {
    setStepIndex(STEP_PHONE);
    setMobile("");
    setName("");
    setOtpDigits(["", "", "", ""]);
    setDevOtp(null);
    setBusy(false);
    attemptedOtpRef.current = null;
  };

  useEffect(() => {
    if (!open) {
      reset();
      return;
    }
    allowCloseRef.current = false;
    setMobile(initialMobile?.replace(/\D/g, "").slice(0, 10) ?? "");
    setName("");
  }, [open, initialMobile]);

  const isNameValid = name.trim().length >= 2;

  useEffect(() => {
    if (open && stepIndex === STEP_PHONE) mobileInputRef.current?.focus();
    if (open && stepIndex === STEP_OTP) nameInputRef.current?.focus();
  }, [open, stepIndex]);

  const formatPhone = (v: string) => {
    const d = v.replace(/\D/g, "").slice(0, 10);
    return d.length > 5 ? `${d.slice(0, 5)} ${d.slice(5)}` : d;
  };

  const rawMobile = mobile.replace(/\D/g, "");
  const isPhoneValid = rawMobile.length === 10;
  const isOtpFull = otpDigits.every((d) => d.length === 1);
  const getOtp = () => otpDigits.join("");

  const showBookingError = (code: string) => {
    toast.error(mapBookingError(code, t), { id: `booking-error-${code}` });
  };

  const handleSendOTP = async () => {
    if (!isPhoneValid || !doctorCode) {
      toast.error(t("enterValidMobile"));
      return;
    }
    setBusy(true);
    try {
      const result = await requestBookOtp(doctorCode, rawMobile);
      setDevOtp(result.devOtp ?? null);
      setOtpDigits(["", "", "", ""]);
      attemptedOtpRef.current = null;
      setStepIndex(STEP_OTP);
      toast.success(t("otpSent"));
    } catch (e) {
      const code = e instanceof Error ? e.message : "request_failed";
      showBookingError(code);
    } finally {
      setBusy(false);
    }
  };

  const handleBook = async () => {
    if (!isOtpFull) {
      toast.error(t("enterOtp"));
      return;
    }
    if (!isNameValid) {
      toast.error(t("errNameRequired"));
      return;
    }

    const otp = getOtp();
    if (attemptedOtpRef.current === otp) {
      toast.message(t("enterOtp"), { id: "booking-retry" });
      return;
    }

    attemptedOtpRef.current = otp;
    const resolvedName = name.trim();

    setBusy(true);
    try {
      const result = await bookToken({
        doctorCode,
        mobile: rawMobile,
        name: resolvedName,
        otpCode: otp,
      });
      savePatientSession({
        mobile: rawMobile,
        name: resolvedName,
        doctorCode,
        loggedInAt: new Date().toISOString(),
      });
      toast.success(t("tokenAllocated"), { id: "booking-success" });
      allowCloseRef.current = true;
      onLoginSuccess(result.tokenNumber);
      onOpenChange(false);
    } catch (e) {
      const code = e instanceof Error ? e.message : "request_failed";
      showBookingError(code);
      if (
        code === "otp_invalid" ||
        code === "otp_not_found_or_expired" ||
        code === "invalid_otp"
      ) {
        attemptedOtpRef.current = null;
        setOtpDigits(["", "", "", ""]);
        otpRefs.current[0]?.focus();
      }
    } finally {
      setBusy(false);
    }
  };

  const closeDialog = () => {
    allowCloseRef.current = true;
    onOpenChange(false);
  };

  const handleOpenChange = (next: boolean) => {
    if (!next && busy) return;
    if (!next && !allowCloseRef.current) {
      toast.message(t("completeBookingFirst"), { id: "booking-incomplete" });
      return;
    }
    if (!next) allowCloseRef.current = false;
    onOpenChange(next);
  };

  const handleOtpChange = (index: number, value: string) => {
    const digit = value.replace(/\D/g, "").slice(0, 1);
    const next = [...otpDigits];
    next[index] = digit;
    setOtpDigits(next);
    attemptedOtpRef.current = null;
    if (digit && otpRefs.current[index + 1]) otpRefs.current[index + 1]?.focus();
  };

  const handleOtpKeyDown = (e: KeyboardEvent<HTMLInputElement>, index: number) => {
    if (e.key === "Backspace" && !otpDigits[index] && otpRefs.current[index - 1]) {
      otpRefs.current[index - 1]?.focus();
    }
    if (e.key === "Enter" && isOtpFull && !busy) {
      e.preventDefault();
      void handleBook();
    }
  };

  const handleOtpPaste = (e: ClipboardEvent<HTMLInputElement>) => {
    const pasted = e.clipboardData.getData("Text").replace(/\D/g, "").slice(0, 4);
    if (!pasted) return;
    e.preventDefault();
    const next = ["", "", "", ""];
    pasted.split("").forEach((c, i) => {
      next[i] = c;
    });
    setOtpDigits(next);
    attemptedOtpRef.current = null;
    otpRefs.current[Math.min(pasted.length, 3)]?.focus();
  };

  useEffect(() => {
    if (!open || stepIndex !== STEP_OTP) return;
    nameInputRef.current?.focus();
  }, [open, stepIndex]);

  const titleMap = {
    [STEP_PHONE]: t("loginNow"),
    [STEP_OTP]: t("weSentOtp"),
  };

  const subMap = {
    [STEP_PHONE]: t("fillQuickLogin"),
    [STEP_OTP]: `${t("checkOtpOn")} ${formatPhone(mobile)}`,
  };

  return (
    <Drawer
      open={open}
      onOpenChange={handleOpenChange}
      dismissible={false}
      repositionInputs={false}
    >
      <DrawerContent
        className="sm:max-w-md sm:mx-auto sm:left-1/2 sm:right-auto sm:top-1/2 sm:bottom-auto sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-[2rem] max-h-[92vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="overflow-y-auto flex-1 min-h-0">
          <StepBar current={stepIndex} />

          <DrawerHeader className="text-center">
            <div className="inline-flex items-center justify-center mx-auto mb-4">
              <FlexzaLogo variant="icon-primary" className="h-14 w-auto" />
            </div>
            <DrawerTitle className="text-2xl">{titleMap[stepIndex]}</DrawerTitle>
            <p className="text-sm text-muted-foreground">{subMap[stepIndex]}</p>
          </DrawerHeader>

          <div className="p-6 space-y-4 pb-8">
            {stepIndex === STEP_PHONE && (
              <form
                className="space-y-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (isPhoneValid && !busy) void handleSendOTP();
                }}
              >
                <div className="relative">
                  <div className="absolute left-0 top-0 bottom-0 w-14 bg-foreground rounded-l-xl flex items-center justify-center">
                    <Phone className="w-5 h-5 text-background" />
                  </div>
                  <Input
                    ref={mobileInputRef}
                    type="tel"
                    placeholder={t("enterMobilePlaceholder")}
                    value={formatPhone(mobile)}
                    onChange={(e: ChangeEvent<HTMLInputElement>) => {
                      setMobile(e.target.value.replace(/\D/g, "").slice(0, 10));
                    }}
                    inputMode="numeric"
                    enterKeyHint="go"
                    maxLength={11}
                    autoFocus
                    disabled={busy}
                    className="pl-20 h-14 rounded-xl bg-input border-0"
                  />
                </div>
                {isPhoneValid ? (
                  <p className="text-sm text-center text-muted-foreground">{t("tapSendOtpHint")}</p>
                ) : null}
                <Button
                  type="submit"
                  disabled={!isPhoneValid || busy}
                  className="w-full h-14 text-base font-semibold rounded-xl"
                >
                  {busy ? (
                    <span className="inline-flex items-center gap-2">
                      <Loader2 className="w-5 h-5 animate-spin" />
                      {t("sendingOtp")}
                    </span>
                  ) : (
                    t("sendOtp")
                  )}
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  disabled={busy}
                  className="w-full"
                  onClick={closeDialog}
                >
                  {t("cancelBooking")}
                </Button>
              </form>
            )}

            {stepIndex === STEP_OTP && (
              <form
                className="space-y-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (isOtpFull && isNameValid && !busy) void handleBook();
                }}
              >
                <div className="space-y-2">
                  <label htmlFor="patient-name" className="text-sm font-medium text-foreground">
                    {t("nameRequiredLabel")}
                  </label>
                  <Input
                    id="patient-name"
                    ref={nameInputRef}
                    type="text"
                    placeholder={t("yourNamePlaceholder")}
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    enterKeyHint="next"
                    className="h-12 rounded-xl bg-input border-0"
                    disabled={busy}
                    autoComplete="name"
                  />
                </div>

                <div className="flex justify-center gap-2">
                  {[0, 1, 2, 3].map((i) => (
                    <Input
                      key={i}
                      ref={(el) => {
                        otpRefs.current[i] = el;
                      }}
                      type="tel"
                      inputMode="numeric"
                      enterKeyHint="done"
                      maxLength={1}
                      value={otpDigits[i]}
                      onChange={(e) => handleOtpChange(i, e.target.value)}
                      onKeyDown={(e) => handleOtpKeyDown(e, i)}
                      onPaste={handleOtpPaste}
                      disabled={busy}
                      className="h-14 w-12 rounded-xl bg-input border-0 text-center text-xl"
                      aria-label={`OTP digit ${i + 1}`}
                    />
                  ))}
                </div>

                {devOtp ? (
                  <p className="text-sm font-medium text-center text-foreground">
                    {t("devOtpLabel")}: {devOtp}
                  </p>
                ) : null}

                <Button
                  type="submit"
                  disabled={!isOtpFull || !isNameValid || busy}
                  className="w-full h-14 text-base font-semibold rounded-xl"
                >
                  {busy ? (
                    <span className="inline-flex items-center gap-2">
                      <Loader2 className="w-5 h-5 animate-spin" />
                      {t("booking")}
                    </span>
                  ) : (
                    t("verifyAndBook")
                  )}
                </Button>

                <div className="flex justify-between items-center text-sm">
                  <button
                    type="button"
                    className="text-muted-foreground"
                    disabled={busy}
                    onClick={() => setStepIndex(STEP_PHONE)}
                  >
                    {t("editMobile")}
                  </button>
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    className="rounded-full"
                    disabled={busy}
                    onClick={() => void handleSendOTP()}
                  >
                    {t("resendOtp")}
                  </Button>
                </div>

                <Button
                  type="button"
                  variant="ghost"
                  disabled={busy}
                  className="w-full"
                  onClick={closeDialog}
                >
                  {t("cancelBooking")}
                </Button>
              </form>
            )}
          </div>
        </div>
      </DrawerContent>
    </Drawer>
  );
};
