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
  myTokenNumber?: number | null;
  initialMobile?: string;
  patientName?: string;
  tokensBookedToday?: number;
  maxTokensPerDay?: number;
  onBooked?: () => void;
}

export const TokenBookingCard = ({
  doctorName,
  doctorCode,
  tokenNumber,
  color = "hsl(var(--white))",
  bookingEnabled = true,
  myTokenNumber = null,
  initialMobile,
  tokensBookedToday,
  maxTokensPerDay = 3,
  onBooked,
}: TokenBookingCardProps) => {
  const [showLogin, setShowLogin] = useState(false);
  const [showSuccess, setShowSuccess] = useState(false);
  const [bookedToken, setBookedToken] = useState(0);
  const { t } = useI18n();

  const displayToken =
    myTokenNumber != null ? String(myTokenNumber) : tokenNumber || "#";

  const handleBookToken = () => {
    if (!bookingEnabled || !doctorCode) return;
    setShowLogin(true);
  };

  const handleLoginSuccess = (token: number) => {
    setBookedToken(token);
    setShowLogin(false);
    setShowSuccess(true);
    onBooked?.();
  };

  const limitReached =
    !bookingEnabled &&
    tokensBookedToday != null &&
    tokensBookedToday >= maxTokensPerDay;

  return (
    <>
      <div className="h-4 bg-foreground rounded-lg -mb-2" />
      <div className="px-3">
        <Card className="relative rounded-none border-0 shadow-none overflow-hidden">
          <CardContent className="pt-8 pb-6 text-center">
            <h3 className="text-lg font-bold mb-4">{doctorName}</h3>
            <div
              className={
                myTokenNumber != null
                  ? "relative mb-6 rounded-2xl bg-primary/10 px-4 py-6 ring-2 ring-primary shadow-lg"
                  : "text-8xl font-bold text-muted-foreground/20 mb-6"
              }
            >
              {myTokenNumber != null ? (
                <>
                  <p className="text-xs font-semibold uppercase tracking-wider text-primary mb-1">
                    {t("yourActiveToken")}
                  </p>
                  <p className="text-7xl font-bold text-primary animate-pulse">
                    #{myTokenNumber}
                  </p>
                </>
              ) : (
                <span className="text-8xl font-bold text-muted-foreground/20">
                  {displayToken.startsWith("#") ? displayToken : `#${displayToken}`}
                </span>
              )}
            </div>
            {myTokenNumber != null && bookingEnabled ? (
              <p className="text-xs text-muted-foreground mb-3">{t("bookAnotherHint")}</p>
            ) : null}
            {limitReached ? (
              <p className="text-sm text-muted-foreground mb-3">{t("errDailyTokenLimit")}</p>
            ) : null}
            <Button onClick={handleBookToken} disabled={!bookingEnabled}>
              {myTokenNumber != null ? t("bookAnotherToken") : t("bookMyToken")}
            </Button>
            {tokensBookedToday != null ? (
              <p className="text-xs text-muted-foreground mt-3">
                {t("tokensTodayLabel")}: {tokensBookedToday}/{maxTokensPerDay}
              </p>
            ) : null}
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
        initialMobile={initialMobile}
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
