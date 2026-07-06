import { BottomNav } from "@/components/BottomNav";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Phone, Mail } from "lucide-react";
import { doctorQueuePath, normalizeDoctorCode } from "@/lib/doctorCode";
import { useClinicProfile } from "@/lib/clinicProfile";
import { Navigate, useParams } from "react-router-dom";

const Help = () => {
  const { doctorCode: raw } = useParams<{ doctorCode: string }>();
  const doctorCode = normalizeDoctorCode(raw ?? "");
  const basePath = doctorQueuePath(doctorCode);
  const { data, isLoading } = useClinicProfile(doctorCode);

  if (!doctorCode) return <Navigate to="/" replace />;

  const phone = data?.clinicPhone;
  const email = data?.clinicEmail;

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <div className="flex items-center gap-3">
          <FlexzaLogo variant="icon-primary" className="h-8 w-auto" />
          <h1 className="text-2xl font-bold">Help & Support</h1>
        </div>

        {isLoading && (
          <p className="text-sm text-muted-foreground">Loading contact…</p>
        )}

        <div className="space-y-4">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center">
                  <Phone className="w-6 h-6 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold">Call clinic</p>
                  <p className="text-sm text-muted-foreground">
                    {phone || "Phone not set"}
                  </p>
                </div>
                {phone ? (
                  <Button variant="outline" size="sm" asChild>
                    <a href={`tel:${phone}`}>Call</a>
                  </Button>
                ) : (
                  <Button variant="outline" size="sm" disabled>
                    Call
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center">
                  <Mail className="w-6 h-6 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold">Email clinic</p>
                  <p className="text-sm text-muted-foreground">
                    {email || "Email not set"}
                  </p>
                </div>
                {email ? (
                  <Button variant="outline" size="sm" asChild>
                    <a href={`mailto:${email}`}>Email</a>
                  </Button>
                ) : (
                  <Button variant="outline" size="sm" disabled>
                    Email
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="pt-2">
          <h2 className="text-lg font-bold mb-4">FAQ</h2>
          <div className="space-y-3">
            <Card>
              <CardContent className="p-4">
                <p className="font-semibold mb-2">How do I book a token?</p>
                <p className="text-sm text-muted-foreground">
                  Tap Book My Token, enter mobile, verify OTP, and get your
                  number. OTP is required every time.
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="font-semibold mb-2">When should I arrive?</p>
                <p className="text-sm text-muted-foreground">
                  Watch the live queue on Home. Come when your number is near.
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      <BottomNav variant="patient" basePath={basePath} doctorCode={doctorCode} />
    </div>
  );
};

export default Help;
