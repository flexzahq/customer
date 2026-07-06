import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { doctorQueuePath, normalizeDoctorCode } from "@/lib/doctorCode";
import { formatTimeRange, useClinicProfile } from "@/lib/clinicProfile";
import { Navigate, useParams } from "react-router-dom";

const Timing = () => {
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorQueuePath(doctorCode);
  const { data, isLoading } = useClinicProfile(doctorCode);

  if (!doctorCode) return <Navigate to="/" replace />;

  const morning = formatTimeRange(data?.morningStart, data?.morningEnd);
  const evening = formatTimeRange(data?.eveningStart, data?.eveningEnd);

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <div>
          <h1 className="text-2xl font-bold">Timing</h1>
          <p className="text-sm text-muted-foreground">
            {data?.clinicName
              ? `${data.clinicName} opening hours`
              : "See opening hours below"}
          </p>
        </div>

        {isLoading && (
          <p className="text-sm text-muted-foreground">Loading timings…</p>
        )}

        {!isLoading && !morning && !evening && (
          <p className="text-sm text-muted-foreground">
            Timings not set yet for this clinic.
          </p>
        )}

        <div className="space-y-4">
          {morning && (
            <Card>
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className="w-6 h-6 bg-primary rounded-full flex items-center justify-center shrink-0 mt-1">
                    <div className="w-2 h-2 bg-primary-foreground rounded-full" />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold mb-2">Morning Time</p>
                    <p className="text-2xl font-bold">{morning}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}

          {evening && (
            <Card>
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className="w-6 h-6 bg-primary rounded-full flex items-center justify-center shrink-0 mt-1">
                    <div className="w-2 h-2 bg-primary-foreground rounded-full" />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold mb-2">Evening Time</p>
                    <p className="text-2xl font-bold">{evening}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      <BottomNav variant="patient" basePath={basePath} doctorCode={doctorCode} />
    </div>
  );
};

export default Timing;
