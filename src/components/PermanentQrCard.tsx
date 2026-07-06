import { useMemo, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { patientQueueUrl } from "@/lib/doctorCode";
import { useI18n } from "@/lib/i18n";
import { Check, Copy, Link2 } from "lucide-react";
import { toast } from "sonner";

interface PermanentQrCardProps {
  doctorCode: string;
  doctorName?: string;
}

export const PermanentQrCard = ({
  doctorCode,
  doctorName,
}: PermanentQrCardProps) => {
  const { t } = useI18n();
  const [copied, setCopied] = useState<"link" | "code" | null>(null);

  const url = useMemo(() => patientQueueUrl(doctorCode), [doctorCode]);

  const copy = async (value: string, kind: "link" | "code") => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(kind);
      toast.success(kind === "link" ? t("linkCopied") : t("codeCopied"));
      setTimeout(() => setCopied(null), 2000);
    } catch {
      toast.error(t("errRequestFailed"));
    }
  };

  return (
    <Card>
      <CardContent className="p-5 space-y-4">
        <div>
          <h3 className="text-lg font-bold">{t("permanentQrTitle")}</h3>
          <p className="text-sm text-muted-foreground mt-1">
            {t("permanentQrDesc")}
          </p>
          {doctorName ? (
            <p className="text-sm font-medium mt-2">{doctorName}</p>
          ) : null}
        </div>

        <div className="flex flex-col sm:flex-row items-center gap-5">
          <div className="rounded-2xl border border-border bg-white p-3 shadow-sm">
            <QRCodeSVG
              value={url}
              size={168}
              level="M"
              includeMargin={false}
              bgColor="#ffffff"
              fgColor="#0f172a"
            />
          </div>

          <div className="flex-1 w-full space-y-3">
            <div>
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">
                {t("doctorCodeLabel")}
              </p>
              <p className="text-2xl font-bold tracking-[0.2em] mt-1">
                {doctorCode}
              </p>
            </div>

            <div>
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex items-center gap-1">
                <Link2 className="w-3.5 h-3.5" />
                {t("patientLink")}
              </p>
              <p className="text-xs text-muted-foreground break-all mt-1 font-mono">
                {url}
              </p>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button
                type="button"
                variant="outline"
                className="rounded-xl"
                onClick={() => void copy(url, "link")}
              >
                {copied === "link" ? (
                  <Check className="w-4 h-4 mr-2" />
                ) : (
                  <Copy className="w-4 h-4 mr-2" />
                )}
                {t("copyLink")}
              </Button>
              <Button
                type="button"
                variant="secondary"
                className="rounded-xl"
                onClick={() => void copy(doctorCode, "code")}
              >
                {copied === "code" ? (
                  <Check className="w-4 h-4 mr-2" />
                ) : (
                  <Copy className="w-4 h-4 mr-2" />
                )}
                {t("copyCode")}
              </Button>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};
