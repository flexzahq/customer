import { TokenBorder } from "@/components/ui/tokenborder";
import { useI18n } from "@/lib/i18n";

interface CurrentTokenBadgesProps {
  currentToken: number | null;
  nextTokens: number[];
}

export const CurrentTokenBadges = ({ currentToken, nextTokens }: CurrentTokenBadgesProps) => {
  const { t } = useI18n();
  return (
    <div className="mb-4 flex gap-3">
      <div className="overflow-hidden rounded-t-lg flex flex-col w-min">
        <div className="flex">
          <div className="shrink-0 bg-primary px-8 pt-5 pb-4 text-primary-foreground">
            <p className="text-md opacity-90">{t("currently")}</p>
            <p className="text-4xl font-bold leading-tight">
              {currentToken != null ? `#${currentToken}` : "#—"}
            </p>
          </div>
        </div>

        <div className="flex-1 -mt-1">
          <TokenBorder color="hsl(var(--primary))" className="" />
        </div>
      </div>
      <div className="flex-1 overflow-hidden rounded-t-lg">
        <div className="flex min-w-0">
          <div className="flex-1 bg-primary-foreground px-6 pt-5 pb-4 text-left">
            <p className="text-md text-foreground">{t("queue")}</p>
            <div className="mt-2 flex items-center whitespace-nowrap text-2xl font-bold leading-tight text-foreground">
              {nextTokens.length === 0 ? (
                <span className="text-muted-foreground">—</span>
              ) : (
                nextTokens.map((token, index) => (
                  <div key={token} className="flex items-center">
                    {index > 0 && <span className="mx-4 h-7 w-px bg-border" />}
                    <span>#{token}</span>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        <div className="flex">
          <TokenBorder color="hsl(var(--primary-foreground))" className="h-[10px] min-w-0 flex-1" />
          <TokenBorder color="hsl(var(--primary-foreground))" className="h-[10px] min-w-0 flex-1" />
        </div>
      </div>
    </div>
  );
};
