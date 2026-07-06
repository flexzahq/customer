import { useMemo, useState } from "react";
import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Search, Loader2 } from "lucide-react";
import { normalizeDoctorCode } from "@/lib/doctorCode";
import {
  fetchStaffQueue,
  initialsFromName,
  type StaffTokenRow,
} from "@/lib/staff";
import { useQueueRealtime } from "@/hooks/use-queue-realtime";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Navigate, useParams } from "react-router-dom";
import { useI18n } from "@/lib/i18n";

const Patients = () => {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorCode ? `/clinic/d/${doctorCode}` : "";

  const { data, isLoading } = useQuery({
    queryKey: ["staff-queue", doctorCode],
    queryFn: () => fetchStaffQueue(doctorCode),
    enabled: Boolean(doctorCode),
    refetchInterval: 60_000,
  });

  useQueueRealtime({
    doctorId: data?.doctorId,
    enabled: Boolean(data?.doctorId),
    onChange: () => {
      void queryClient.invalidateQueries({ queryKey: ["staff-queue", doctorCode] });
    },
  });

  const patients = useMemo(() => {
    if (!data) return [] as StaffTokenRow[];
    const all = [
      ...(data.serving ? [data.serving] : []),
      ...data.waiting,
      ...data.skipped,
      ...data.completed,
    ];
    const byMobile = new Map<string, StaffTokenRow>();
    for (const row of all) {
      if (!byMobile.has(row.patient_mobile)) {
        byMobile.set(row.patient_mobile, row);
      }
    }
    const list = Array.from(byMobile.values());
    const q = search.trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (row) =>
        row.patient_name?.toLowerCase().includes(q) ||
        row.patient_mobile.includes(q),
    );
  }, [data, search]);

  if (!doctorCode) return <Navigate to="/clinic" replace />;

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">{t("navPatients")}</h1>

        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-muted-foreground" />
          <Input
            placeholder={t("search")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10 h-12"
          />
        </div>

        {isLoading && (
          <div className="flex justify-center py-8">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
          </div>
        )}

        <div className="space-y-3">
          {!isLoading && patients.length === 0 && (
            <p className="text-sm text-muted-foreground text-center py-4">
              {t("emptyList")}
            </p>
          )}
          {patients.map((patient) => (
            <Card key={patient.patient_mobile}>
              <CardContent className="p-4">
                <div className="flex items-center gap-3">
                  <Avatar className="w-12 h-12 bg-muted">
                    <AvatarFallback className="text-muted-foreground font-semibold">
                      {initialsFromName(
                        patient.patient_name,
                        patient.patient_mobile,
                      )}
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <p className="font-semibold">
                      {patient.patient_name || patient.patient_mobile}
                    </p>
                    <p className="text-sm text-muted-foreground">
                      {patient.patient_mobile}
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

export default Patients;
