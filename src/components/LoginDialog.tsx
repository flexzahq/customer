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

interface LoginDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  doctorCode: string;
  onLoginSuccess: (token: number) => void;
}

const STEPS = 4;
const STEP_PHONE = 0;
const STEP_OTP = 1;
const STEP_NAME = 2;
const STEP_TOKEN = 3;

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
    case "already_in_queue":
      return t("errAlreadyInQueue");
    default:
      return t("errRequestFailed");
  }
}

export const LoginDialog = ({
  open,
  onOpenChange,
  doctorCode,
  onLoginSuccess,
}: LoginDialogProps) => {
  const [stepIndex, setStepIndex] = useState(STEP_PHONE);
  const [mobile, setMobile] = useState("");
  const [name, setName] = useState("");
  const [otpDigits, setOtpDigits] = useState<string[]>(["", "", "", ""]);
  const [assignedToken, setAssignedToken] = useState<number | null>(null);
  const [devOtp, setDevOtp] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const mobileInputRef = useRef<HTMLInputElement>(null);
  const otpRefs = useRef<Array<HTMLInputElement | null>>([]);
  const { t } = useI18n();

  const reset = () => {
    setStepIndex(STEP_PHONE);
    setMobile("");
    setName("");
    setOtpDigits(["", "", "", ""]);
    setAssignedToken(null);
    setDevOtp(null);
    setBusy(false);
  };

  useEffect(() => {
    if (!open) reset();
  }, [open]);

  useEffect(() => {
    if (open && stepIndex === STEP_PHONE) mobileInputRef.current?.focus();
    if (open && stepIndex === STEP_OTP) otpRefs.current[0]?.focus();
  }, [open, stepIndex]);

  const formatPhone = (v: string) => {
    const d = v.replace(/\D/g, "").slice(0, 10);
    return d.length > 5 ? `${d.slice(0, 5)} ${d.slice(5)}` : d;
  };

  const rawMobile = mobile.replace(/\D/g, "");
  const isPhoneValid = rawMobile.length === 10;
  const isOtpFull = otpDigits.every((d) => d.length === 1);
  const getOtp = () => otpDigits.join("");

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
      setStepIndex(STEP_OTP);
      toast.success(t("otpSent"));
    } catch (e) {
      const code = e instanceof Error ? e.message : "request_failed";
      toast.error(mapBookingError(code, t));
    } finally {
      setBusy(false);
    }
  };

  /** OTP every book — never skip. Only advance to name after 4 digits entered. */
  const handleOtpContinue = () => {
    if (!isOtpFull) {
      toast.error(t("enterOtp"));
      return;
    }
    const stored = localStorage.getItem("flexza_patient");
    if (stored) {
      try {
        const existing = JSON.parse(stored) as { mobile?: string; name?: string };
        if (existing.mobile === rawMobile && existing.name) {
          setName(existing.name);
        }
      } catch {
        // ignore
      }
    }
    setStepIndex(STEP_NAME);
  };

  const handleBook = async (resolvedName: string) => {
    if (!isOtpFull) {
      toast.error(t("enterOtp"));
      setStepIndex(STEP_OTP);
      return;
    }
    setBusy(true);
    try {
      const result = await bookToken({
        doctorCode,
        mobile: rawMobile,
        name: resolvedName,
        otpCode: getOtp(),
      });
      setAssignedToken(result.tokenNumber);
      localStorage.setItem(
        "flexza_patient",
        JSON.stringify({ mobile: rawMobile, name: resolvedName }),
      );
      setStepIndex(STEP_TOKEN);
    } catch (e) {
      const code = e instanceof Error ? e.message : "request_failed";
      toast.error(mapBookingError(code, t));
      if (
        code === "otp_invalid" ||
        code === "otp_not_found_or_expired" ||
        code === "invalid_otp"
      ) {
        setStepIndex(STEP_OTP);
      }
    } finally {
      setBusy(false);
    }
  };

  const handleDone = () => {
    if (assignedToken != null) onLoginSuccess(assignedToken);
    onOpenChange(false);
  };

  const handleOtpChange = (index: number, value: string) => {
    const digit = value.replace(/\D/g, "").slice(0, 1);
    const next = [...otpDigits];
    next[index] = digit;
    setOtpDigits(next);
    if (digit && otpRefs.current[index + 1]) otpRefs.current[index + 1]?.focus();
  };

  const handleOtpKeyDown = (e: KeyboardEvent<HTMLInputElement>, index: number) => {
    if (e.key === "Backspace" && !otpDigits[index] && otpRefs.current[index - 1]) {
      otpRefs.current[index - 1]?.focus();
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
    otpRefs.current[Math.min(pasted.length, 3)]?.focus();
  };

  const titleMap = {
    [STEP_PHONE]: t("loginNow"),
    [STEP_OTP]: t("weSentOtp"),
    [STEP_NAME]: t("yourName"),
    [STEP_TOKEN]: t("yourToken"),
  };

  const subMap = {
    [STEP_PHONE]: t("fillQuickLogin"),
    [STEP_OTP]: `${t("checkOtpOn")} ${formatPhone(mobile)}`,
    [STEP_NAME]: t("enterNameSub"),
    [STEP_TOKEN]: t("tokenAllocated"),
  };

  return (
    <Drawer open={open} onOpenChange={onOpenChange}>
      <DrawerContent
        className="sm:max-w-md sm:mx-auto sm:left-1/2 sm:right-auto sm:top-1/2 sm:bottom-auto sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-[2rem]"
        onClick={(e) => e.stopPropagation()}
      >
        <StepBar current={stepIndex} />

        <DrawerHeader className="text-center">
          <div className="inline-flex items-center justify-center mx-auto mb-4">
            <FlexzaLogo variant="icon-primary" className="h-14 w-auto" />
          </div>
          <DrawerTitle className="text-2xl">{titleMap[stepIndex]}</DrawerTitle>
          <p className="text-sm text-muted-foreground">{subMap[stepIndex]}</p>
        </DrawerHeader>

        <div className="p-6 space-y-4">
          {stepIndex === STEP_PHONE && (
            <>
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
                  maxLength={11}
                  autoFocus
                  disabled={busy}
                  className="pl-20 h-14 rounded-xl bg-input border-0"
                />
              </div>
              <Button
                onClick={() => void handleSendOTP()}
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
            </>
          )}

          {stepIndex === STEP_OTP && (
            <>
              <div className="flex justify-center gap-2">
                {[0, 1, 2, 3].map((i) => (
                  <Input
                    key={i}
                    ref={(el) => {
                      otpRefs.current[i] = el;
                    }}
                    type="tel"
                    inputMode="numeric"
                    maxLength={1}
                    value={otpDigits[i]}
                    onChange={(e) => handleOtpChange(i, e.target.value)}
                    onKeyDown={(e) => handleOtpKeyDown(e, i)}
                    onPaste={handleOtpPaste}
                    disabled={busy}
                    className="h-14 w-12 rounded-xl bg-input border-0 text-center text-xl"
                    autoFocus={i === 0}
                  />
                ))}
              </div>

              {devOtp ? (
                <p className="text-sm font-medium text-center text-foreground">
                  {t("devOtpLabel")}: {devOtp}
                </p>
              ) : null}

              <Button
                onClick={handleOtpContinue}
                disabled={!isOtpFull || busy}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                {t("verify")}
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
                  variant="secondary"
                  size="sm"
                  className="rounded-full"
                  disabled={busy}
                  onClick={() => void handleSendOTP()}
                >
                  {t("resendOtp")}
                </Button>
              </div>
            </>
          )}

          {stepIndex === STEP_NAME && (
            <>
              <Input
                type="text"
                placeholder={t("yourNamePlaceholder")}
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="h-14 rounded-xl bg-input border-0"
                autoFocus
                disabled={busy}
              />
              <Button
                onClick={() => void handleBook(name.trim())}
                disabled={!name.trim() || busy}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                {busy ? (
                  <span className="inline-flex items-center gap-2">
                    <Loader2 className="w-5 h-5 animate-spin" />
                    {t("booking")}
                  </span>
                ) : (
                  t("save")
                )}
              </Button>
              <Button
                onClick={() => void handleBook("")}
                variant="secondary"
                disabled={busy}
                className="w-full h-12 text-sm rounded-xl"
              >
                {t("skip")}
              </Button>
            </>
          )}

          {stepIndex === STEP_TOKEN && (
            <>
              <div className="text-center space-y-2">
                <div className="text-5xl font-bold text-primary">#{assignedToken}</div>
                <p className="text-base text-muted-foreground">
                  {t("yourTokenNumberAllocated")}
                </p>
              </div>
              <Button
                onClick={handleDone}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                {t("backToHome")}
              </Button>
            </>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  );
};
