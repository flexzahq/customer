import { Card, CardContent } from "@/components/ui/card";
import { useI18n, type TranslationKey } from "@/lib/i18n";
import type { PatientVisit } from "@/lib/patientDashboard";

function formatVisitDate(iso: string): string {
  if (!iso) return "";
  try {
    return new Intl.DateTimeFormat("en-IN", {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: "Asia/Kolkata",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

function statusLabel(status: string, t: (k: TranslationKey) => string): string {
  switch (status) {
    case "completed":
      return t("statusCompleted");
    case "serving":
      return t("statusServing");
    case "waiting":
      return t("statusWaiting");
    case "skipped":
      return t("statusSkipped");
    case "cancelled":
      return t("statusCancelled");
    default:
      return status;
  }
}

interface PatientHistoryListProps {
  visits: PatientVisit[];
  loading?: boolean;
}

export const PatientHistoryList = ({ visits, loading }: PatientHistoryListProps) => {
  const { t } = useI18n();

  if (loading) {
    return (
      <p className="text-sm text-muted-foreground px-1">{t("loadingHistory")}</p>
    );
  }

  if (visits.length === 0) {
    return (
      <p className="text-sm text-muted-foreground px-1">{t("noHistoryYet")}</p>
    );
  }

  return (
    <div className="space-y-2">
      {visits.map((visit) => (
        <Card key={visit.tokenId} className="border-0 shadow-sm">
          <CardContent className="p-4 flex items-center justify-between gap-3">
            <div>
              <p className="font-bold text-lg">#{visit.tokenNumber}</p>
              <p className="text-xs text-muted-foreground">
                {formatVisitDate(visit.bookedAt)}
              </p>
            </div>
            <span className="text-sm font-medium capitalize text-muted-foreground">
              {statusLabel(visit.status, t)}
            </span>
          </CardContent>
        </Card>
      ))}
    </div>
  );
};
