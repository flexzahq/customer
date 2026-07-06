import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { FlexzaLogo } from "@/components/FlexzaLogo";
import { BRAND } from "@/lib/brand";
import { useI18n } from "@/lib/i18n";

interface HeaderProps {
  clinicName?: string;
  subtitle?: string;
  userInitials?: string;
  /** When true, show full Flexza wordmark (no clinic yet). */
  brandOnly?: boolean;
}

export const Header = ({
  clinicName,
  subtitle,
  userInitials,
  brandOnly = false,
}: HeaderProps) => {
  const { lang, setLang } = useI18n();
  const showClinic = !brandOnly && Boolean(clinicName);

  return (
    <header
      className="relative left-1/2 right-1/2 w-screen -ml-[50vw] -mr-[50vw]"
      style={{ background: "var(--gradient-header)" }}
    >
      <div className="mx-auto flex max-w-[1280px] items-center justify-between px-4 py-3 md:px-6 md:py-4">
        <div className="flex items-center gap-3 min-w-0">
          {showClinic ? (
            <>
              <FlexzaLogo
                variant="icon-primary"
                className="h-10 w-8 shrink-0 drop-shadow-sm"
              />
              <div className="min-w-0">
                <h1 className="font-heading text-xl md:text-2xl font-semibold text-foreground truncate">
                  {clinicName}
                </h1>
                {subtitle ? (
                  <p className="text-xs md:text-sm text-foreground truncate">
                    {subtitle}
                  </p>
                ) : null}
              </div>
            </>
          ) : (
            <FlexzaLogo
              variant="horizontal-white"
              className="h-9 md:h-10 max-w-[200px]"
            />
          )}
        </div>
        <div className="flex items-center gap-3 shrink-0">
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
          {userInitials ? (
            <Avatar className="w-10 h-10 bg-primary shadow-sm">
              <AvatarFallback className="bg-primary text-primary-foreground font-semibold font-heading">
                {userInitials}
              </AvatarFallback>
            </Avatar>
          ) : (
            <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center">
              <FlexzaLogo variant="icon-white" className="h-5 w-4" />
            </div>
          )}
        </div>
      </div>
      <span className="sr-only">{BRAND.name}</span>
    </header>
  );
};
