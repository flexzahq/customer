import { Header } from "@/components/Header";
import { BottomNav } from "@/components/BottomNav";
import { PermanentQrCard } from "@/components/PermanentQrCard";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Users, ChevronRight, Loader2 } from "lucide-react";
import { normalizeDoctorCode } from "@/lib/doctorCode";
import {
  fetchStaffQueue,
  formatTokenTime,
  initialsFromName,
} from "@/lib/staff";
import { useQueueRealtime } from "@/hooks/use-queue-realtime";
import { useQuery } from "@tanstack/react-query";
import { Link, Navigate, useParams } from "react-router-dom";
import { useI18n } from "@/lib/i18n";

const Clinic = () => {
  const { t } = useI18n();
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorCode ? `/clinic/d/${doctorCode}` : "";

  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["staff-queue", doctorCode],
    queryFn: () => fetchStaffQueue(doctorCode),
    enabled: Boolean(doctorCode),
    refetchInterval: 60_000,
  });

  useQueueRealtime({
    doctorId: data?.doctorId,
    enabled: Boolean(data?.doctorId),
    onChange: () => {
      void refetch();
    },
  });

  if (!doctorCode) return <Navigate to="/clinic" replace />;

  const recent = [
    ...(data?.serving ? [data.serving] : []),
    ...(data?.waiting ?? []),
  ].slice(0, 5);

  return (
    <div className="min-h-screen bg-background pb-20">
      <Header
        clinicName={data?.clinicName}
        subtitle={data?.doctorName}
        userInitials={data?.doctorName?.slice(0, 2).toUpperCase()}
      />

      <div className="p-4 space-y-6">
        {isLoading && (
          <div className="flex justify-center py-10">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
          </div>
        )}

        {isError && (
          <div className="space-y-2">
            <p className="text-sm text-destructive">{t("errRequestFailed")}</p>
            <Button variant="outline" size="sm" onClick={() => refetch()}>
              Retry
            </Button>
          </div>
        )}

        {data && (
          <>
            <Card>
              <CardContent className="p-6">
                <div className="flex items-start justify-between mb-4">
                  <div>
                    <h2 className="text-4xl font-bold">{data.totalToday}</h2>
                    <p className="text-sm text-muted-foreground">
                      {t("totalTokensToday")}
                    </p>
                  </div>
                  <span className="text-xs font-semibold rounded-full border px-3 py-1 uppercase tracking-wide">
                    {data.sessionStatus ?? "—"}
                  </span>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2 text-muted-foreground">
                      <Users className="w-4 h-4" />
                      <span className="text-sm">{t("inQueue")}</span>
                    </div>
                    <p className="text-2xl font-bold">{data.waitingCount}</p>
                  </div>
                  <div className="space-y-1">
                    <p className="text-sm text-muted-foreground">
                      {t("doctorCodeLabel")}
                    </p>
                    <p className="text-2xl font-bold tracking-wider">
                      {data.doctorCode}
                    </p>
                  </div>
                </div>

                {isFetching && !isLoading && (
                  <p className="mt-3 text-xs text-muted-foreground">Updating…</p>
                )}

                <Button asChild className="w-full mt-4 h-11 rounded-xl">
                  <Link to={`${basePath}/token`}>{t("manageQueue")}</Link>
                </Button>
              </CardContent>
            </Card>

            <PermanentQrCard
              doctorCode={data.doctorCode}
              doctorName={data.doctorName}
            />

            <div>
              <div className="flex items-center justify-between mb-4">
                <div>
                  <h3 className="text-lg font-bold">{t("recentArrived")}</h3>
                  <p className="text-sm text-muted-foreground">
                    {t("recentArrivedDesc")}
                  </p>
                </div>
              </div>

              {recent.length === 0 ? (
                <p className="text-sm text-muted-foreground">{t("noQueueTitle")}</p>
              ) : (
                <div className="space-y-3">
                  {recent.map((token) => (
                    <Card key={token.id}>
                      <CardContent className="p-4">
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3">
                            <Avatar className="w-10 h-10 bg-muted">
                              <AvatarFallback className="text-muted-foreground">
                                {initialsFromName(
                                  token.patient_name,
                                  token.patient_mobile,
                                )}
                              </AvatarFallback>
                            </Avatar>
                            <div>
                              <p className="font-semibold">
                                {token.patient_name || token.patient_mobile}
                              </p>
                              <p className="text-sm text-muted-foreground">
                                {token.patient_mobile}
                              </p>
                            </div>
                          </div>
                          <div className="flex items-center gap-2">
                            <span className="text-lg font-bold">#{token.number}</span>
                            <ChevronRight className="w-5 h-5 text-muted-foreground" />
                          </div>
                        </div>
                        <p className="text-xs text-muted-foreground mt-2">
                          {formatTokenTime(token.booked_at)}
                        </p>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              )}
            </div>
          </>
        )}
      </div>

      <BottomNav variant="clinic" basePath={basePath} />
    </div>
  );
};

export default Clinic;
