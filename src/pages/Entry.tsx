import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { useI18n } from "@/lib/i18n";
import { BRAND } from "@/lib/brand";
import {
  doctorQueuePath,
  extractDoctorCode,
  isValidDoctorCode,
  normalizeDoctorCode,
} from "@/lib/doctorCode";
import { resolveDoctorCode } from "@/lib/queue";
import { Camera, Hash, Loader2, X } from "lucide-react";
import { toast } from "sonner";

const Entry = () => {
  const { t, lang, setLang } = useI18n();
  const navigate = useNavigate();
  const [codeInput, setCodeInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [scanning, setScanning] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanLoopRef = useRef<number | null>(null);

  const stopScan = useCallback(() => {
    if (scanLoopRef.current != null) {
      cancelAnimationFrame(scanLoopRef.current);
      scanLoopRef.current = null;
    }
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setScanning(false);
  }, []);

  useEffect(() => () => stopScan(), [stopScan]);

  const goToDoctor = async (raw: string) => {
    const code = extractDoctorCode(raw);
    if (!code || !isValidDoctorCode(code)) {
      toast.error(t("invalidDoctorCode"));
      return;
    }

    setLoading(true);
    try {
      const resolved = await resolveDoctorCode(code);
      if (!resolved) {
        toast.error(t("doctorCodeNotFound"));
        return;
      }
      navigate(doctorQueuePath(resolved.doctorCode));
    } catch {
      toast.error(t("doctorCodeNotFound"));
    } finally {
      setLoading(false);
    }
  };

  const handleContinue = (e: React.FormEvent) => {
    e.preventDefault();
    void goToDoctor(codeInput);
  };

  const handleScanResult = (value: string) => {
    stopScan();
    setCodeInput(normalizeDoctorCode(extractDoctorCode(value) ?? value));
    void goToDoctor(value);
  };

  const startScan = async () => {
    // Prefer native BarcodeDetector when available (Chrome/Android)
    const Detector = (
      window as unknown as {
        BarcodeDetector?: new (opts: { formats: string[] }) => {
          detect: (source: ImageBitmapSource) => Promise<Array<{ rawValue: string }>>;
        };
      }
    ).BarcodeDetector;

    if (!Detector) {
      toast.message(t("scanFallbackHint"));
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
        audio: false,
      });
      streamRef.current = stream;
      setScanning(true);

      await new Promise<void>((resolve) => {
        requestAnimationFrame(() => resolve());
      });

      const video = videoRef.current;
      if (!video) {
        stopScan();
        return;
      }
      video.srcObject = stream;
      await video.play();

      const detector = new Detector({ formats: ["qr_code"] });

      const tick = async () => {
        if (!videoRef.current || videoRef.current.readyState < 2) {
          scanLoopRef.current = requestAnimationFrame(() => {
            void tick();
          });
          return;
        }
        try {
          const codes = await detector.detect(videoRef.current);
          if (codes[0]?.rawValue) {
            handleScanResult(codes[0].rawValue);
            return;
          }
        } catch {
          // keep scanning
        }
        scanLoopRef.current = requestAnimationFrame(() => {
          void tick();
        });
      };

      void tick();
    } catch {
      stopScan();
      toast.error(t("cameraPermissionDenied"));
    }
  };

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <div className="flex justify-end p-4">
        <div className="inline-flex overflow-hidden rounded-full border border-border bg-background">
          <button
            type="button"
            onClick={() => setLang("en")}
            className={`px-3 py-1 text-xs font-semibold ${lang === "en" ? "bg-primary text-primary-foreground" : "text-foreground"}`}
          >
            EN
          </button>
          <button
            type="button"
            onClick={() => setLang("gu")}
            className={`px-3 py-1 text-xs font-semibold ${lang === "gu" ? "bg-primary text-primary-foreground" : "text-foreground"}`}
          >
            GU
          </button>
        </div>
      </div>

      <div className="flex-1 flex items-center justify-center p-4 pb-10">
        <div className="w-full max-w-md space-y-6">
          <div className="text-center space-y-3">
            <FlexzaLogo
              variant="horizontal-black"
              className="h-12 w-auto max-w-[220px] mx-auto"
            />
            <p className="text-sm text-muted-foreground">{BRAND.tagline}</p>
            <h1 className="text-2xl font-bold font-heading">{t("entryTitle")}</h1>
            <p className="text-sm text-muted-foreground">{t("entrySubtitle")}</p>
          </div>

          <Card>
            <CardContent className="p-5 space-y-4">
              <form onSubmit={handleContinue} className="space-y-3">
                <label className="text-sm font-semibold flex items-center gap-2">
                  <Hash className="w-4 h-4 text-primary" />
                  {t("doctorCodeLabel")}
                </label>
                <Input
                  value={codeInput}
                  onChange={(e) =>
                    setCodeInput(normalizeDoctorCode(e.target.value).slice(0, 12))
                  }
                  placeholder={t("doctorCodePlaceholder")}
                  className="h-14 rounded-xl text-center text-lg tracking-widest uppercase font-semibold"
                  autoCapitalize="characters"
                  autoCorrect="off"
                  spellCheck={false}
                  disabled={loading}
                />
                <p className="text-xs text-muted-foreground">
                  {t("doctorCodeHint")}
                </p>
                <Button
                  type="submit"
                  className="w-full h-12 rounded-xl"
                  disabled={loading || codeInput.length < 4}
                >
                  {loading ? (
                    <Loader2 className="w-5 h-5 animate-spin" />
                  ) : (
                    t("continueToClinic")
                  )}
                </Button>
              </form>

              <div className="relative py-1">
                <div className="absolute inset-0 flex items-center">
                  <span className="w-full border-t border-border" />
                </div>
                <div className="relative flex justify-center text-xs uppercase">
                  <span className="bg-card px-2 text-muted-foreground">{t("or")}</span>
                </div>
              </div>

              {!scanning ? (
                <Button
                  type="button"
                  variant="outline"
                  className="w-full h-12 rounded-xl"
                  onClick={() => void startScan()}
                  disabled={loading}
                >
                  <Camera className="w-5 h-5 mr-2" />
                  {t("scanQr")}
                </Button>
              ) : (
                <div className="space-y-3">
                  <div className="relative overflow-hidden rounded-xl bg-black aspect-[3/4]">
                    <video
                      ref={videoRef}
                      className="h-full w-full object-cover"
                      muted
                      playsInline
                    />
                    <button
                      type="button"
                      onClick={stopScan}
                      className="absolute top-3 right-3 rounded-full bg-background/90 p-2"
                      aria-label="Close scanner"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                  <p className="text-xs text-center text-muted-foreground">
                    {t("scanPointHint")}
                  </p>
                </div>
              )}
            </CardContent>
          </Card>

          <p className="text-center text-sm text-muted-foreground">
            {t("staffLoginPrompt")}{" "}
            <Link to="/clinic" className="text-primary font-semibold">
              {t("staffLoginLink")}
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
};

export default Entry;
