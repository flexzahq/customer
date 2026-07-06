import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Bell, Loader2 } from "lucide-react";
import { normalizeDoctorCode } from "@/lib/doctorCode";
import { supabase } from "@/lib/supabase";
import { useQuery } from "@tanstack/react-query";
import { Navigate, useParams } from "react-router-dom";
import { useI18n } from "@/lib/i18n";

type StaffNotification = {
  id: string;
  title: string;
  body: string;
  audience: string;
  sent_at: string | null;
  created_at: string;
};

async function fetchStaffNotifications(
  doctorCode: string,
): Promise<StaffNotification[]> {
  const { data, error } = await supabase.rpc("list_staff_notifications", {
    p_doctor_code: doctorCode,
  });
  if (error) throw error;
  return (
    (data as { notifications?: StaffNotification[] }).notifications ?? []
  );
}

const Notifications = () => {
  const { t } = useI18n();
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorCode ? `/clinic/d/${doctorCode}` : "";

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["staff-notifications", doctorCode],
    queryFn: () => fetchStaffNotifications(doctorCode),
    enabled: Boolean(doctorCode),
    refetchInterval: 30_000,
  });

  if (!doctorCode) return <Navigate to="/clinic" replace />;

  const notifications = data ?? [];

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">{t("navNotification")}</h1>
        <p className="text-sm text-muted-foreground">
          Messages from Flexza HQ for your clinic.
        </p>

        {isLoading && (
          <div className="flex justify-center py-8">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
          </div>
        )}

        {isError && (
          <p className="text-sm text-destructive">
            Could not load notifications.{" "}
            <button type="button" className="underline" onClick={() => refetch()}>
              Retry
            </button>
          </p>
        )}

        <div className="space-y-3">
          {!isLoading && notifications.length === 0 && (
            <p className="text-sm text-muted-foreground text-center py-4">
              {t("emptyList")}
            </p>
          )}
          {notifications.map((notification) => (
            <Card key={notification.id}>
              <CardContent className="p-4">
                <div className="flex gap-3">
                  <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center shrink-0">
                    <Bell className="w-5 h-5 text-primary" />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold">{notification.title}</p>
                    <p className="text-sm text-muted-foreground mt-1 whitespace-pre-wrap">
                      {notification.body}
                    </p>
                    <p className="text-xs text-muted-foreground mt-2">
                      {notification.sent_at
                        ? new Date(notification.sent_at).toLocaleString()
                        : ""}{" "}
                      · {notification.audience}
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>

      <BottomNav variant="clinic" basePath={basePath} />
    </div>
  );
};

export default Notifications;
