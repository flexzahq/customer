import { BRAND } from "@/lib/brand";
import { cn } from "@/lib/utils";

type LogoVariant =
  | "icon-primary"
  | "icon-black"
  | "icon-white"
  | "horizontal-black"
  | "horizontal-white";

const SRC: Record<LogoVariant, string> = {
  "icon-primary": BRAND.iconPrimary,
  "icon-black": BRAND.iconBlack,
  "icon-white": BRAND.iconWhite,
  "horizontal-black": BRAND.logoHorizontalBlack,
  "horizontal-white": BRAND.logoHorizontalWhite,
};

interface FlexzaLogoProps {
  variant?: LogoVariant;
  className?: string;
  alt?: string;
}

export const FlexzaLogo = ({
  variant = "icon-primary",
  className,
  alt = BRAND.name,
}: FlexzaLogoProps) => {
  const isHorizontal = variant.startsWith("horizontal");

  return (
    <img
      src={SRC[variant]}
      alt={alt}
      className={cn(
        isHorizontal ? "h-8 w-auto object-contain" : "h-10 w-auto object-contain",
        className,
      )}
      draggable={false}
    />
  );
};
