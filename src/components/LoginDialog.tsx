import { useEffect, useRef, useState, type ChangeEvent, type KeyboardEvent, type ClipboardEvent } from "react";
import { Drawer, DrawerContent, DrawerHeader, DrawerTitle } from "@/components/ui/drawer";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Phone } from "lucide-react";
import { toast } from "sonner";
import { useI18n } from "@/lib/i18n";

interface LoginDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onLoginSuccess: (token: number) => void;
}

// ─── Step progress bar ────────────────────────────────────────────────────────
const STEPS = 4; // phone → otp → name → token

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

// step index map
const STEP_PHONE = 0;
const STEP_OTP   = 1;
const STEP_NAME  = 2;
const STEP_TOKEN = 3;

export const LoginDialog = ({ open, onOpenChange, onLoginSuccess }: LoginDialogProps) => {
  const [stepIndex, setStepIndex] = useState(STEP_PHONE);
  const [mobile, setMobile]       = useState("");
  const [name, setName]           = useState("");
  const [otpDigits, setOtpDigits] = useState<string[]>(["", "", "", ""]);
  const [assignedToken, setAssignedToken] = useState<number | null>(null);

  // TODO: replace with real OTP from API
  const DUMMY_OTP = "1234";

  const mobileInputRef = useRef<HTMLInputElement>(null);
  const otpRefs        = useRef<Array<HTMLInputElement | null>>([]);
  const { t } = useI18n();

  // ─── Reset on close ──────────────────────────────────────────────────────
  const reset = () => {
    setStepIndex(STEP_PHONE);
    setMobile("");
    setName("");
    setOtpDigits(["", "", "", ""]);
    setAssignedToken(null);
  };

  useEffect(() => { if (!open) reset(); }, [open]);

  useEffect(() => {
    if (open && stepIndex === STEP_PHONE) mobileInputRef.current?.focus();
    if (open && stepIndex === STEP_OTP)   otpRefs.current[0]?.focus();
  }, [open, stepIndex]);

  // ─── Helpers ─────────────────────────────────────────────────────────────
  const formatPhone = (v: string) => {
    const d = v.replace(/\D/g, "").slice(0, 10);
    return d.length > 5 ? `${d.slice(0, 5)} ${d.slice(5)}` : d;
  };

  const rawMobile    = mobile.replace(/\D/g, "");
  const isPhoneValid = rawMobile.length === 10;
  const isOtpFull    = otpDigits.every((d) => d.length === 1);
  const getOtp       = () => otpDigits.join("");

  // ─── Handlers ────────────────────────────────────────────────────────────

  // STEP 0 → 1
  const handleSendOTP = () => {
    // TODO: call API to send OTP to `rawMobile`
    setStepIndex(STEP_OTP);
  };

  // STEP 1 → 2
  const handleVerifyOTP = () => {
    if (!isOtpFull) { toast.error(t("enterOtp")); return; }
    if (getOtp() !== DUMMY_OTP) {          // TODO: replace with API verify
      toast.error("Invalid OTP, please try again");
      return;
    }
    // Check if user already has a name stored (returning user skip name step)
    const stored = localStorage.getItem("user");
    const existing = stored ? JSON.parse(stored) : null;
    if (existing?.name) {
      setName(existing.name);
      allocateToken(existing.name);        // skip to token directly
    } else {
      setStepIndex(STEP_NAME);
    }
  };

  // STEP 2 → 3
  const handleContinueName = () => allocateToken(name.trim());
  const handleSkipName     = () => allocateToken("");

  const allocateToken = (resolvedName: string) => {
    const token = Math.floor(Math.random() * 90) + 10; // TODO: receive from API
    setAssignedToken(token);
    localStorage.setItem("user", JSON.stringify({ mobile: rawMobile, name: resolvedName, token }));
    setStepIndex(STEP_TOKEN);
  };

  // STEP 3 → done
  const handleDone = () => {
    if (assignedToken) onLoginSuccess(assignedToken);
    onOpenChange(false);
  };

  // ─── OTP input helpers ───────────────────────────────────────────────────
  const handleOtpChange = (index: number, value: string) => {
    const digit = value.replace(/\D/g, "").slice(0, 1);
    const next  = [...otpDigits]; next[index] = digit;
    setOtpDigits(next);
    if (digit && otpRefs.current[index + 1]) otpRefs.current[index + 1]?.focus();
  };

  const handleOtpKeyDown = (e: KeyboardEvent<HTMLInputElement>, index: number) => {
    if (e.key === "Backspace" && !otpDigits[index] && otpRefs.current[index - 1])
      otpRefs.current[index - 1]?.focus();
  };

  const handleOtpPaste = (e: ClipboardEvent<HTMLInputElement>) => {
    const pasted = e.clipboardData.getData("Text").replace(/\D/g, "").slice(0, 4);
    if (!pasted) return;
    const next = ["", "", "", ""];
    pasted.split("").forEach((c, i) => { next[i] = c; });
    setOtpDigits(next);
    otpRefs.current[Math.min(pasted.length, 3)]?.focus();
  };

  // ─── Step meta ───────────────────────────────────────────────────────────
  const titleMap = {
    [STEP_PHONE]: t("loginNow"),
    [STEP_OTP]:   t("weSentOtp"),
    [STEP_NAME]:  t("yourName") ?? "Your name",
    [STEP_TOKEN]: t("yourToken"),
  };

  const subMap = {
    [STEP_PHONE]: t("fillQuickLogin"),
    [STEP_OTP]:   `${t("checkOtpOn")} ${formatPhone(mobile)}`,
    [STEP_NAME]:  t("enterNameSub") ?? "We'll use this to personalise your experience",
    [STEP_TOKEN]: t("tokenAllocated"),
  };

  // ─── Render ──────────────────────────────────────────────────────────────
  return (
    <Drawer open={open} onOpenChange={onOpenChange}>
      <DrawerContent
        className="sm:max-w-md sm:mx-auto sm:left-1/2 sm:right-auto sm:top-1/2 sm:bottom-auto sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-[2rem]"
        onClick={(e) => e.stopPropagation()}
      >

        {/* ── Step bar ── */}
        <StepBar current={stepIndex} />

        <DrawerHeader className="text-center">
          <div className="inline-flex items-center justify-center w-14 h-14 bg-primary rounded-2xl mx-auto mb-4">
            <div className="grid grid-cols-2 gap-1">
              {[0,1,2,3].map((k) => (
                <div key={k} className="w-2.5 h-2.5 bg-primary-foreground rounded-sm" />
              ))}
            </div>
          </div>
          <DrawerTitle className="text-2xl">{titleMap[stepIndex]}</DrawerTitle>
          <p className="text-sm text-muted-foreground">{subMap[stepIndex]}</p>
        </DrawerHeader>

        <div className="p-6 space-y-4">

          {/* ── STEP 0: Phone ── */}
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
                  className="pl-20 h-14 rounded-xl bg-input border-0"
                />
              </div>
              <Button
                onClick={handleSendOTP}
                disabled={!isPhoneValid}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                {t("sendOtp")}
              </Button>
            </>
          )}

          {/* ── STEP 1: OTP ── */}
          {stepIndex === STEP_OTP && (
            <>
              <div className="flex justify-center gap-2">
                {[0, 1, 2, 3].map((i) => (
                  <Input
                    key={i}
                    ref={(el) => (otpRefs.current[i] = el)}
                    type="tel"
                    inputMode="numeric"
                    maxLength={1}
                    value={otpDigits[i]}
                    onChange={(e) => handleOtpChange(i, e.target.value)}
                    onKeyDown={(e) => handleOtpKeyDown(e as any, i)}
                    onPaste={handleOtpPaste}
                    className="h-14 w-12 rounded-xl bg-input border-0 text-center text-xl"
                    autoFocus={i === 0}
                  />
                ))}
              </div>

              {/* TODO: remove in production */}
              <p className="text-sm font-medium text-center text-foreground">
                {`${t("useDummyOtp")}: ${DUMMY_OTP}`}
              </p>

              <Button
                onClick={handleVerifyOTP}
                disabled={!isOtpFull}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                {t("verify")}
              </Button>

              <div className="flex justify-between items-center text-sm">
                <button
                  className="text-muted-foreground"
                  onClick={() => setStepIndex(STEP_PHONE)}
                >
                  {t("editMobile")}
                </button>
                <Button variant="secondary" size="sm" className="rounded-full" onClick={handleSendOTP}>
                  {t("resendOtp")}
                </Button>
              </div>
            </>
          )}

          {/* ── STEP 2: Name ── */}
          {stepIndex === STEP_NAME && (
            <>
              <Input
                type="text"
                placeholder={t("yourNamePlaceholder")}
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="h-14 rounded-xl bg-input border-0"
                autoFocus
              />
              <Button
                onClick={handleContinueName}
                disabled={!name.trim()}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                {t("save") ?? "Save"}
              </Button>
              <Button
                onClick={handleSkipName}
                variant="secondary"
                className="w-full h-12 text-sm rounded-xl"
              >
                {t("skip") ?? "Skip"}
              </Button>
            </>
          )}

          {/* ── STEP 3: Token ── */}
          {stepIndex === STEP_TOKEN && (
            <>
              <div className="text-center space-y-2">
                <div className="text-5xl font-bold text-primary">#{assignedToken}</div>
                <p className="text-base text-muted-foreground">{t("yourTokenNumberAllocated")}</p>
              </div>
              <Button onClick={handleDone} className="w-full h-14 text-base font-semibold rounded-xl">
                {t("backToHome")}
              </Button>
            </>
          )}

        </div>
      </DrawerContent>
    </Drawer>
  );
};