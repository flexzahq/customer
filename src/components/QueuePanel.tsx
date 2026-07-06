import { TokenBorder } from "@/components/ui/tokenborder";
import { useI18n } from "@/lib/i18n";
import { cn } from "@/lib/utils";

interface QueuePanelProps {
  currentToken: number | null;
  waitingTokens: number[];
  myTokenNumber?: number | null;
}

export const QueuePanel = ({
  currentToken,
  waitingTokens,
  myTokenNumber = null,
}: QueuePanelProps) => {
  const { t } = useI18n();

  return (
    <div className="mb-4 flex gap-3">
      <div className="overflow-hidden rounded-t-lg flex flex-col w-min shrink-0">
        <div className="flex">
          <div className="shrink-0 bg-primary px-8 pt-5 pb-4 text-primary-foreground">
            <p className="text-md opacity-90">{t("currently")}</p>
            <p className="text-4xl font-bold leading-tight">
              {currentToken != null ? `#${currentToken}` : "#—"}
            </p>
          </div>
        </div>
        <div className="flex-1 -mt-1">
          <TokenBorder color="hsl(var(--primary))" />
        </div>
      </div>

      <div className="flex-1 min-w-0 overflow-hidden rounded-t-lg flex flex-col">
        <div className="flex-1 bg-primary-foreground px-4 pt-5 pb-3 text-left min-h-[88px] flex flex-col">
          <p className="text-md text-foreground font-medium">{t("queue")}</p>
          <div className="mt-2 flex-1 overflow-y-auto max-h-32 pr-1">
            {waitingTokens.length === 0 ? (
              <span className="text-muted-foreground text-lg">—</span>
            ) : (
              <div className="flex flex-wrap gap-2">
                {waitingTokens.map((token) => {
                  const isMine = myTokenNumber != null && token === myTokenNumber;
                  return (
                    <span
                      key={token}
                      className={cn(
                        "inline-flex items-center rounded-lg px-2.5 py-1 text-lg font-bold",
                        isMine
                          ? "bg-primary text-primary-foreground ring-4 ring-primary/40 shadow-lg scale-105 animate-pulse"
                          : "bg-muted text-foreground",
                      )}
                    >
                      #{token}
                      {isMine ? (
                        <span className="ml-1.5 text-xs font-medium opacity-90">
                          {t("you")}
                        </span>
                      ) : null}
                    </span>
                  );
                })}
              </div>
            )}
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
