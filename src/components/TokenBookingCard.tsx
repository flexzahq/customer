import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { LoginDialog } from "./LoginDialog";
import { BookingSuccessDialog } from "./BookingSuccessDialog";
import { TokenBorder } from "@/components/ui/tokenborder";
import { useI18n } from "@/lib/i18n";


interface TokenBookingCardProps {
  doctorName: string;
  tokenNumber?: string;
  color?: string;
}

export const TokenBookingCard = ({ doctorName, tokenNumber, color = "hsl(var(--white))" }: TokenBookingCardProps) => {
  const [showLogin, setShowLogin] = useState(false);
  const [showSuccess, setShowSuccess] = useState(false);
  const [bookedToken, setBookedToken] = useState(0);
  const { t } = useI18n();

  const handleBookToken = () => {
    const user = localStorage.getItem("user");
    if (!user) {
      setShowLogin(true);
    } else {
      const newToken = Math.floor(Math.random() * 50) + 1;
      setBookedToken(newToken);
      setShowSuccess(true);
    }
  };

  const handleLoginSuccess = (token: number) => {
    setBookedToken(token);
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
              {tokenNumber || "#"}
            </div>
            <Button
              onClick={handleBookToken}
            >
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
