import { Header } from "@/components/Header";
import { BottomNav } from "@/components/BottomNav";
import { CurrentTokenBadges } from "@/components/CurrentTokenBadges";
import { QueueStats } from "@/components/QueueStats";
import { TokenBookingCard } from "@/components/TokenBookingCard";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/lib/i18n";
import { doctorQueuePath, normalizeDoctorCode } from "@/lib/doctorCode";
import { fetchLiveQueueByDoctorCode } from "@/lib/queue";
import { useQueueRealtime } from "@/hooks/use-queue-realtime";
import { useQuery } from "@tanstack/react-query";
import { Link, Navigate, useParams } from "react-router-dom";

const Home = () => {
  const { t } = useI18n();
  const { doctorCode: rawCode } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(rawCode ?? "");
  const basePath = doctorCode ? doctorQueuePath(doctorCode) : "";

  const { data, isLoading, isError, error, refetch, isFetching } = useQuery({
    queryKey: ["live-queue", doctorCode],
    queryFn: () => fetchLiveQueueByDoctorCode(doctorCode),
    enabled: Boolean(doctorCode),
    // Realtime is primary; polling is a slow backup only
    refetchInterval: 60_000,
  });

  useQueueRealtime({
    doctorId: data?.doctor?.id,
    enabled: Boolean(data?.doctor?.id),
    onChange: () => {
      void refetch();
    },
  });

  const handleBooked = () => {
    void refetch();
  };

  if (!doctorCode) {
    return <Navigate to="/" replace />;
  }

  const hasDoctor = data?.hasDoctor ?? false;
  const hasQueue = data?.hasQueue ?? false;
  const doctorName = data?.doctor?.name ?? "";
  const clinicName = data?.clinic?.name;
  const clinicSubtitle = data?.clinic?.subtitle ?? undefined;

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
            <Button variant="outline" size="sm" onClick={() => refetch()}>
              Retry
            </Button>
          </div>
        )}

        {!isLoading && !isError && data && !hasDoctor && (
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
                  <CurrentTokenBadges
                    currentToken={data!.currentToken}
                    nextTokens={data!.nextTokens}
                  />
                  <QueueStats
                    totalAhead={data!.waitingCount}
                    estimatedTime={data!.estimatedTime}
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
                  {data!.doctor?.code}
                </span>
              </p>
            </div>

            <div className="w-full">
              <TokenBookingCard
                doctorName={doctorName}
                doctorCode={doctorCode}
                bookingEnabled={Boolean(doctorName)}
                onBooked={handleBooked}
              />
            </div>
          </div>
        )}

        <div className="px-4 md:px-8">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-bold">{t("recentHistory")}</h3>
            <Button variant="ghost" size="sm" className="text-primary">
              {t("seeAll")}
            </Button>
          </div>
          <p className="text-sm text-muted-foreground">{t("pastHistoryDesc")}</p>
        </div>
      </div>

      <BottomNav variant="patient" basePath={basePath} doctorCode={doctorCode} />
    </div>
  );
};

export default Home;
