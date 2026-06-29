import * as React from "react";
import { cn } from "@/lib/utils";
import { TokenBorder } from "@/components/ui/tokenborder";

interface TokenCardProps extends React.HTMLAttributes<HTMLDivElement> {
  color?: string;
}

const TokenCard = React.forwardRef<HTMLDivElement, TokenCardProps>(
  ({ color = "hsl(var(--primary))", className, children, ...props }, ref) => {
    const style = { "--tokencard-color": color } as React.CSSProperties;

    return (
      <div className="token-card overflow-hidden relative">
        {/* Card */}
        <div
          ref={ref}
          style={style}
          className={cn(
            "overflow-hidden relative",
            "bg-[var(--tokencard-color)]",
            className
          )}
          {...props}
        >
          {/* Card inner content */}
          <div className="px-4 pt-4 pb-2">
            {children}
          </div>
        </div>

        {/* Token Border OUTSIDE below the card */}
        <TokenBorder color={color} />

      </div>
    );
  }
);

TokenCard.displayName = "TokenCard";

export { TokenCard };
