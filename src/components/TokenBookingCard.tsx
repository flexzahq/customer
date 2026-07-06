import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { LoginDialog } from "./LoginDialog";
import { BookingSuccessDialog } from "./BookingSuccessDialog";
import { TokenBorder } from "@/components/ui/tokenborder";
import { useI18n } from "@/lib/i18n";

interface TokenBookingCardProps {
  doctorName: string;
  doctorCode: string;
  tokenNumber?: string;
  color?: string;
  bookingEnabled?: boolean;
  /** Patient's own booked token (if any) */
  myTokenNumber?: number | null;
  onBooked?: () => void;
}

export const TokenBookingCard = ({
  doctorName,
  doctorCode,
  tokenNumber,
  color = "hsl(var(--white))",
  bookingEnabled = true,
  myTokenNumber = null,
  onBooked,
}: TokenBookingCardProps) => {
  const [showLogin, setShowLogin] = useState(false);
  const [showSuccess, setShowSuccess] = useState(false);
  const [bookedToken, setBookedToken] = useState(0);
  const { t } = useI18n();

  const displayToken =
    myTokenNumber != null
      ? String(myTokenNumber)
      : tokenNumber || "#";

  const handleBookToken = () => {
    if (!bookingEnabled || !doctorCode) return;
    // OTP required on every book — always open full flow
    setShowLogin(true);
  };

  const handleLoginSuccess = (token: number) => {
    setBookedToken(token);
    onBooked?.();
    setTimeout(() => setShowSuccess(true), 300);
  };

  return (
    <>
      <div className="h-4 bg-foreground rounded-lg -mb-2" />
      <div className="px-3">
        <Card className="relative rounded-none border-0 shadow-none overflow-hidden">
          <CardContent className="pt-8 pb-6 text-center">
            <h3 className="text-lg font-bold mb-4">{doctorName}</h3>
            <div className="text-8xl font-bold text-muted-foreground/20 mb-6">
              {displayToken.startsWith("#") ? displayToken : `#${displayToken}`}
            </div>
            <Button onClick={handleBookToken} disabled={!bookingEnabled}>
              {t("bookMyToken")}
            </Button>
          </CardContent>
        </Card>
        <div className="overflow-hidden shadow--lg">
          <TokenBorder color={color} />
        </div>
      </div>

      <LoginDialog
        open={showLogin}
        onOpenChange={setShowLogin}
        doctorCode={doctorCode}
        onLoginSuccess={handleLoginSuccess}
      />

      <BookingSuccessDialog
        open={showSuccess}
        onOpenChange={setShowSuccess}
        tokenNumber={bookedToken}
      />
    </>
  );
};
