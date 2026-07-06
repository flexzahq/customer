import { Header } from "@/components/Header";
import { BottomNav } from "@/components/BottomNav";
import { QueuePanel } from "@/components/QueuePanel";
import { QueueStats } from "@/components/QueueStats";
import { TokenBookingCard } from "@/components/TokenBookingCard";
import { PatientHistoryList } from "@/components/PatientHistoryList";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/lib/i18n";
import { doctorQueuePath, normalizeDoctorCode } from "@/lib/doctorCode";
import { fetchPublicQueue, estimateWaitMinutes } from "@/lib/publicQueue";
import { fetchPatientDashboard } from "@/lib/patientDashboard";
import { loadPatientSession } from "@/lib/patientSession";
import { useQueueRealtime } from "@/hooks/use-queue-realtime";
import { useQuery } from "@tanstack/react-query";
import { Link, Navigate, useParams } from "react-router-dom";
import { useState } from "react";

function formatEta(minutes: number): string {
  if (minutes <= 0) return "0m";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

const Home = () => {
  const { t } = useI18n();
  const { doctorCode: rawCode } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(rawCode ?? "");
  const basePath = doctorCode ? doctorQueuePath(doctorCode) : "";

  const [sessionTick, setSessionTick] = useState(0);
  const patientSession = doctorCode ? loadPatientSession(doctorCode) : null;

  const {
    data: queueData,
    isLoading,
    isError,
    error,
    refetch: refetchQueue,
    isFetching,
  } = useQuery({
    queryKey: ["public-queue", doctorCode],
    queryFn: () => fetchPublicQueue(doctorCode),
    enabled: Boolean(doctorCode),
    refetchInterval: 60_000,
  });

  const {
    data: dashboard,
    isLoading: dashboardLoading,
    refetch: refetchDashboard,
  } = useQuery({
    queryKey: ["patient-dashboard", doctorCode, patientSession?.mobile, sessionTick],
    queryFn: () => fetchPatientDashboard(doctorCode, patientSession!.mobile),
    enabled: Boolean(doctorCode && patientSession?.mobile),
    refetchInterval: 60_000,
  });

  useQueueRealtime({
    doctorId: queueData?.doctor?.id,
    enabled: Boolean(queueData?.doctor?.id),
    onChange: () => {
      void refetchQueue();
      void refetchDashboard();
    },
  });

  const myTokenNumber =
    dashboard?.activeToken?.tokenNumber ?? null;

  const myWaitMinutes = queueData
    ? estimateWaitMinutes(
        queueData.waitingTokens,
        myTokenNumber,
        queueData.minutesPerPatient,
      )
    : 0;

  const handleBooked = () => {
    setSessionTick((n) => n + 1);
    void refetchQueue();
    void refetchDashboard();
  };

  if (!doctorCode) {
    return <Navigate to="/" replace />;
  }

  const hasDoctor = queueData?.hasDoctor ?? false;
  const hasQueue = queueData?.hasQueue ?? false;
  const doctorName = queueData?.doctor?.name ?? "";
  const clinicName = queueData?.clinic?.clinicName;
  const clinicSubtitle = queueData?.clinic?.clinicSubtitle ?? undefined;

  const canBook = patientSession
    ? (dashboard?.canBook ?? true)
    : true;

  const historyVisits = patientSession ? (dashboard?.history ?? []) : [];

  return (
    <div className="min-h-screen">
      <div className="cir-container">
        <div className="bg-circle mx-auto" />
      </div>

      <Header
        brandOnly={!hasDoctor}
        clinicName={clinicName}
        subtitle={
          hasDoctor
            ? [clinicSubtitle, doctorName].filter(Boolean).join(" · ") ||
              doctorName
            : undefined
        }
      />

      <div className="py-6 space-y-6 pb-24">
        {patientSession ? (
          <div className="px-4 md:px-8">
            <p className="text-sm text-muted-foreground">
              {t("loggedInAs")}{" "}
              <span className="font-semibold text-foreground">
                {patientSession.name}
              </span>
              {" · "}
              {patientSession.mobile.replace(/(\d{5})(\d{5})/, "$1 $2")}
            </p>
          </div>
        ) : null}

        {isLoading && (
          <p className="px-4 md:px-8 text-sm text-muted-foreground">
            Loading queue…
          </p>
        )}

        {isError && (
          <div className="px-4 md:px-8 space-y-2">
            <p className="text-sm text-destructive">
              Could not load queue
              {error instanceof Error ? `: ${error.message}` : ""}
            </p>
            <Button variant="outline" size="sm" onClick={() => refetchQueue()}>
              Retry
            </Button>
          </div>
        )}

        {!isLoading && !isError && queueData && !hasDoctor && (
          <div className="px-4 md:px-8 text-center py-10 space-y-4">
            <FlexzaLogo variant="icon-primary" className="h-20 w-auto mx-auto" />
            <h2 className="text-xl font-bold">{t("doctorCodeNotFound")}</h2>
            <p className="text-sm text-muted-foreground">{t("entrySubtitle")}</p>
            <Button asChild className="rounded-xl">
              <Link to="/">{t("backToEntry")}</Link>
            </Button>
          </div>
        )}

        {!isLoading && !isError && hasDoctor && (
          <div className="px-4 md:px-8 grid grid-cols-1 gap-2 md:grid-cols-[7fr_3fr] md:items-start">
            <div>
              {hasQueue ? (
                <>
                  <QueuePanel
                    currentToken={queueData!.currentToken}
                    waitingTokens={queueData!.waitingTokens}
                    myTokenNumber={myTokenNumber}
                  />
                  <QueueStats
                    totalAhead={
                      myTokenNumber != null
                        ? queueData!.waitingTokens.filter((n) => n < myTokenNumber).length
                        : queueData!.waitingCount
                    }
                    estimatedTime={
                      myTokenNumber != null
                        ? formatEta(myWaitMinutes)
                        : queueData!.estimatedTime
                    }
                  />
                </>
              ) : (
                <div className="text-center py-8">
                  <div className="w-48 h-48 mx-auto mb-4 relative">
                    <div className="absolute inset-0 flex items-center justify-center">
                      <div className="w-32 h-32 bg-primary/20 rounded-full" />
                    </div>
                    <div className="absolute inset-0 flex items-center justify-center">
                      <FlexzaLogo
                        variant="icon-primary"
                        className="h-16 w-auto"
                      />
                    </div>
                  </div>
                  <h2 className="text-xl font-bold mb-2">{t("noQueueTitle")}</h2>
                  <p className="text-sm text-muted-foreground">
                    {t("noQueueDesc")}
                  </p>
                </div>
              )}
              {isFetching && !isLoading && (
                <p className="mt-2 text-xs text-muted-foreground">Updating…</p>
              )}
              <p className="mt-3 text-xs text-muted-foreground">
                {t("doctorCodeLabel")}:{" "}
                <span className="font-semibold tracking-wider">
                  {queueData!.doctor?.code}
                </span>
              </p>
            </div>

            <div className="w-full">
              <TokenBookingCard
                doctorName={doctorName}
                doctorCode={doctorCode}
                bookingEnabled={canBook}
                myTokenNumber={myTokenNumber}
                initialMobile={patientSession?.mobile}
                tokensBookedToday={dashboard?.tokensBookedToday}
                maxTokensPerDay={dashboard?.maxTokensPerDay ?? queueData?.maxTokensPerDay}
                onBooked={handleBooked}
              />
            </div>
          </div>
        )}

        {patientSession ? (
          <div className="px-4 md:px-8">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold">{t("recentHistory")}</h3>
            </div>
            <PatientHistoryList
              visits={historyVisits}
              loading={dashboardLoading}
            />
          </div>
        ) : (
          <div className="px-4 md:px-8">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold">{t("recentHistory")}</h3>
            </div>
            <p className="text-sm text-muted-foreground">{t("pastHistoryDesc")}</p>
          </div>
        )}
      </div>

      <BottomNav variant="patient" basePath={basePath} doctorCode={doctorCode} />
    </div>
  );
};

export default Home;
