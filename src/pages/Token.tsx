import { useMemo, useState } from "react";
import { Header } from "@/components/Header";
import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Users, Clock, Ticket, Search, Loader2 } from "lucide-react";
import { normalizeDoctorCode } from "@/lib/doctorCode";
import {
  completeToken,
  fetchStaffQueue,
  formatTokenTime,
  initialsFromName,
  setSessionStatus,
  skipToken,
  type StaffTokenRow,
} from "@/lib/staff";
import { useQueueRealtime } from "@/hooks/use-queue-realtime";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Navigate, useParams } from "react-router-dom";
import { useI18n } from "@/lib/i18n";
import { toast } from "sonner";

const Token = () => {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorCode ? `/clinic/d/${doctorCode}` : "";

  const [activeTab, setActiveTab] = useState<"current" | "skipped" | "completed">(
    "current",
  );
  const [search, setSearch] = useState("");

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["staff-queue", doctorCode],
    queryFn: () => fetchStaffQueue(doctorCode),
    enabled: Boolean(doctorCode),
    refetchInterval: 60_000,
  });

  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: ["staff-queue", doctorCode] });

  useQueueRealtime({
    doctorId: data?.doctorId,
    enabled: Boolean(data?.doctorId),
    onChange: () => {
      void invalidate();
    },
  });

  const completeMutation = useMutation({
    mutationFn: async () => {
      if (!data?.sessionId) throw new Error("no_session");
      await completeToken(data.sessionId);
    },
    onSuccess: () => {
      toast.success(t("markedComplete"));
      void invalidate();
    },
    onError: () => toast.error(t("errRequestFailed")),
  });

  const skipMutation = useMutation({
    mutationFn: async () => {
      if (!data?.sessionId) throw new Error("no_session");
      await skipToken(data.sessionId);
    },
    onSuccess: () => {
      toast.success(t("markedSkipped"));
      void invalidate();
    },
    onError: () => toast.error(t("errRequestFailed")),
  });

  const pauseMutation = useMutation({
    mutationFn: async (allowBooking: boolean) => {
      if (!data?.sessionId) throw new Error("no_session");
      await setSessionStatus(data.sessionId, allowBooking ? "open" : "paused");
    },
    onSuccess: (_, allowBooking) => {
      toast.success(allowBooking ? t("bookingOpened") : t("bookingPaused"));
      void invalidate();
    },
    onError: () => toast.error(t("errRequestFailed")),
  });

  const canBookNew = data?.sessionStatus === "open";
  const busy =
    completeMutation.isPending ||
    skipMutation.isPending ||
    pauseMutation.isPending;

  const list = useMemo(() => {
    if (!data) return [] as StaffTokenRow[];
    const source =
      activeTab === "current"
        ? data.waiting
        : activeTab === "skipped"
          ? data.skipped
          : data.completed;
    const q = search.trim().toLowerCase();
    if (!q) return source;
    return source.filter(
      (row) =>
        row.patient_name?.toLowerCase().includes(q) ||
        row.patient_mobile.includes(q) ||
        String(row.number).includes(q),
    );
  }, [activeTab, data, search]);

  if (!doctorCode) return <Navigate to="/clinic" replace />;

  const tabs = [
    { id: "current" as const, label: t("tabCurrent") },
    { id: "skipped" as const, label: t("tabSkipped") },
    { id: "completed" as const, label: t("tabCompleted") },
  ];

  const estMinutes = data ? data.waitingCount * 10 : 0;
  const estLabel =
    estMinutes <= 0
      ? "0m"
      : estMinutes < 60
        ? `${estMinutes}m`
        : `${Math.floor(estMinutes / 60)}h ${estMinutes % 60}m`;

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
              <CardContent className="p-4">
                <div className="flex items-center justify-between mb-4">
                  <div>
                    <p className="text-sm text-muted-foreground mb-1">
                      {t("currently")}
                    </p>
                    <p className="text-3xl font-bold">
                      {data.serving ? `#${data.serving.number}` : "#—"}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold">
                      {data.serving
                        ? data.serving.patient_name || data.serving.patient_mobile
                        : t("noServingToken")}
                    </p>
                    {data.serving && (
                      <p className="text-xs text-muted-foreground">
                        {formatTokenTime(data.serving.booked_at)}
                      </p>
                    )}
                  </div>
                </div>

                <div className="flex gap-2 mb-4">
                  <Button
                    variant="outline"
                    className="flex-1 h-12"
                    disabled={!data.serving || !data.sessionId || busy}
                    onClick={() => skipMutation.mutate()}
                  >
                    {t("skip")}
                  </Button>
                  <Button
                    className="flex-1 h-12"
                    disabled={!data.sessionId || busy}
                    onClick={() => completeMutation.mutate()}
                  >
                    {t("markComplete")}
                  </Button>
                </div>

                <div className="grid grid-cols-3 gap-3">
                  <div className="text-center">
                    <Users className="w-5 h-5 mx-auto mb-1 text-muted-foreground" />
                    <p className="text-xs text-muted-foreground mb-1">
                      {t("inQueue")}
                    </p>
                    <p className="text-2xl font-bold">{data.waitingCount}</p>
                  </div>
                  <div className="text-center">
                    <Clock className="w-5 h-5 mx-auto mb-1 text-muted-foreground" />
                    <p className="text-xs text-muted-foreground mb-1">
                      {t("estTime")}
                    </p>
                    <p className="text-2xl font-bold">{estLabel}</p>
                  </div>
                  <div className="text-center">
                    <Ticket className="w-5 h-5 mx-auto mb-1 text-muted-foreground" />
                    <p className="text-xs text-muted-foreground mb-1">
                      {t("totalToday")}
                    </p>
                    <p className="text-2xl font-bold">{data.totalToday}</p>
                  </div>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4 flex items-center justify-between gap-3">
                <span className="font-medium">{t("canBookNew")}</span>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    variant={canBookNew ? "default" : "outline"}
                    disabled={!data.sessionId || busy}
                    onClick={() => pauseMutation.mutate(true)}
                    className="min-w-[60px]"
                  >
                    {t("yes")}
                  </Button>
                  <Button
                    size="sm"
                    variant={!canBookNew ? "default" : "outline"}
                    disabled={!data.sessionId || busy}
                    onClick={() => pauseMutation.mutate(false)}
                    className="min-w-[60px]"
                  >
                    {t("no")}
                  </Button>
                </div>
              </CardContent>
            </Card>

            <div className="flex gap-2">
              {tabs.map((tab) => (
                <Button
                  key={tab.id}
                  variant={activeTab === tab.id ? "default" : "outline"}
                  onClick={() => setActiveTab(tab.id)}
                  className="flex-1"
                >
                  {tab.label}
                </Button>
              ))}
            </div>

            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                placeholder={t("search")}
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="pl-10"
              />
            </div>

            <div className="space-y-3">
              {list.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-4">
                  {t("emptyList")}
                </p>
              ) : (
                list.map((token) => (
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
                            <p className="text-xs text-muted-foreground">
                              {formatTokenTime(token.booked_at)}
                            </p>
                          </div>
                        </div>
                        <p className="text-xl font-bold">#{token.number}</p>
                      </div>
                    </CardContent>
                  </Card>
                ))
              )}
            </div>
          </>
        )}
      </div>

      <BottomNav variant="clinic" basePath={basePath} />
    </div>
  );
};

export default Token;
