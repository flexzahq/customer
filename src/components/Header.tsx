import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { useI18n } from "@/lib/i18n";

interface HeaderProps {
  clinicName?: string;
  subtitle?: string;
  userInitials?: string;
}

export const Header = ({ 
  clinicName,
  subtitle,
  userInitials = "JU"
}: HeaderProps) => {
  const { lang, setLang, t } = useI18n();
  const displayedClinicName = clinicName ?? t("clinicName");
  const displayedSubtitle = subtitle ?? t("subtitle");

  return (
    <header
      className="relative left-1/2 right-1/2 w-screen -ml-[50vw] -mr-[50vw]"
      style={{ background: "var(--gradient-header)" }}
    >
      <div className="mx-auto flex max-w-[1280px] items-center justify-between px-4 py-3 md:px-6 md:py-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-primary rounded-lg flex items-center justify-center shadow-sm">
            <div className="w-6 h-6 bg-primary-foreground rounded-full" />
          </div>
          <div>
            <h1 className="font-heading text-xl md:text-2xl font-semibold text-foreground">{displayedClinicName}</h1>
            <p className="text-xs md:text-sm text-foreground">{displayedSubtitle}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className="inline-flex overflow-hidden rounded-full border border-border bg-background">
            <button
              type="button"
              onClick={() => setLang("en")}
              className={`px-3 py-1 text-xs font-semibold ${lang === "en" ? "bg-primary text-primary-foreground" : "text-foreground"}`}
            >
              EN
            </button>
            <button
              type="button"
              onClick={() => setLang("gu")}
              className={`px-3 py-1 text-xs font-semibold ${lang === "gu" ? "bg-primary text-primary-foreground" : "text-foreground"}`}
            >
              GU
            </button>
          </div>
          <Avatar className="w-10 h-10 bg-primary shadow-sm">
          <AvatarFallback className="bg-primary text-primary-foreground font-semibold font-heading">
            {userInitials}
          </AvatarFallback>
        </Avatar>
        </div>
      </div>
    </header>
  );
};
