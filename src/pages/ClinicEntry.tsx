import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { useI18n } from "@/lib/i18n";
import {
  extractDoctorCode,
  isValidDoctorCode,
  normalizeDoctorCode,
} from "@/lib/doctorCode";
import { resolveDoctorCode } from "@/lib/queue";
import { openTodaySession } from "@/lib/staff";
import { Hash, Loader2 } from "lucide-react";
import { toast } from "sonner";

const ClinicEntry = () => {
  const { t, lang, setLang } = useI18n();
  const navigate = useNavigate();
  const [codeInput, setCodeInput] = useState("");
  const [loading, setLoading] = useState(false);

  const handleContinue = async (e: React.FormEvent) => {
    e.preventDefault();
    const code = extractDoctorCode(codeInput);
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
      // Ensure today's session exists (open)
      await openTodaySession(resolved.doctorId);
      navigate(`/clinic/d/${resolved.doctorCode}`);
    } catch {
      toast.error(t("errRequestFailed"));
    } finally {
      setLoading(false);
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
            <h1 className="text-2xl font-bold font-heading">{t("staffEntryTitle")}</h1>
            <p className="text-sm text-muted-foreground">{t("staffEntrySubtitle")}</p>
          </div>

          <Card>
            <CardContent className="p-5 space-y-4">
              <form onSubmit={(e) => void handleContinue(e)} className="space-y-3">
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
                  disabled={loading}
                />
                <Button
                  type="submit"
                  className="w-full h-12 rounded-xl"
                  disabled={loading || codeInput.length < 4}
                >
                  {loading ? (
                    <Loader2 className="w-5 h-5 animate-spin" />
                  ) : (
                    t("openStaffDashboard")
                  )}
                </Button>
              </form>
            </CardContent>
          </Card>

          <p className="text-center text-sm text-muted-foreground">
            <Link to="/" className="text-primary font-semibold">
              {t("backToEntry")}
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
};

export default ClinicEntry;
