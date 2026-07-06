import { BottomNav } from "@/components/BottomNav";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { Card, CardContent } from "@/components/ui/card";
import { doctorQueuePath, normalizeDoctorCode } from "@/lib/doctorCode";
import { useClinicProfile } from "@/lib/clinicProfile";
import { Navigate, useParams } from "react-router-dom";

const About = () => {
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorQueuePath(doctorCode);
  const { data, isLoading } = useClinicProfile(doctorCode);

  if (!doctorCode) return <Navigate to="/" replace />;

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">About</h1>

        <Card>
          <CardContent className="p-6 space-y-4">
            {isLoading && (
              <p className="text-sm text-muted-foreground">Loading clinic…</p>
            )}

            {!isLoading && data && (
              <>
                <div>
                  <h2 className="text-xl font-bold">{data.clinicName}</h2>
                  {data.clinicSubtitle && (
                    <p className="text-muted-foreground">{data.clinicSubtitle}</p>
                  )}
                  <p className="text-sm text-muted-foreground mt-1">
                    {data.doctorName}
                  </p>
                </div>

                {data.clinicAbout ? (
                  <p className="text-sm whitespace-pre-wrap">{data.clinicAbout}</p>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    No clinic description yet.
                  </p>
                )}

                <div className="space-y-1 text-sm border-t pt-4">
                  {data.clinicPhone && (
                    <p>
                      <span className="font-semibold">Phone:</span>{" "}
                      {data.clinicPhone}
                    </p>
                  )}
                  {data.clinicEmail && (
                    <p>
                      <span className="font-semibold">Email:</span>{" "}
                      {data.clinicEmail}
                    </p>
                  )}
                  {data.clinicAddress && (
                    <p>
                      <span className="font-semibold">Address:</span>{" "}
                      {data.clinicAddress}
                    </p>
                  )}
                </div>
              </>
            )}

            {!isLoading && !data && (
              <div className="space-y-3">
                <FlexzaLogo
                  variant="horizontal-black"
                  className="h-10 w-auto max-w-[200px]"
                />
                <p className="text-sm text-muted-foreground">
                  Clinic not found for this doctor code.
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <BottomNav variant="patient" basePath={basePath} doctorCode={doctorCode} />
    </div>
  );
};

export default About;
