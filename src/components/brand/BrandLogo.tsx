import logoLight from "@/assets/logo.png";
import logoDark from "@/assets/logo-dark.png";
import { useTheme } from "@/hooks/useTheme";

/**
 * Standardized CHOPCHOP logo sizes — visual height in pixels.
 * Use these tokens instead of ad-hoc h-X classes so the wordmark
 * appears at a consistent visual scale across every surface.
 */
export type BrandLogoSize = "sm" | "md" | "lg" | "xl";

const SIZE_CLASS: Record<BrandLogoSize, string> = {
  sm: "h-7",   // ~28px — compact headers
  md: "h-9",   // ~36px — standard app header, auth, page headers
  lg: "h-14",  // ~56px — splash, onboarding, drawers
  xl: "h-20",  // ~80px — hero / splash only
};

type Props = Omit<React.ImgHTMLAttributes<HTMLImageElement>, "src"> & {
  /** Force a specific variant regardless of current theme. */
  variant?: "auto" | "light" | "dark";
  /** Standardized visual size token. Defaults to "md". */
  size?: BrandLogoSize;
};

export function BrandLogo({
  variant = "auto",
  size = "md",
  alt = "CHOPCHOP",
  className = "",
  loading = "eager",
  decoding = "async",
  ...rest
}: Props) {
  const { isDark } = useTheme();
  const src =
    variant === "dark" ? logoDark : variant === "light" ? logoLight : isDark ? logoDark : logoLight;
  return (
    <img
      src={src}
      alt={alt}
      loading={loading}
      decoding={decoding}
      className={`${SIZE_CLASS[size]} w-auto object-contain select-none ${className}`.trim()}
      {...rest}
    />
  );
}

export function useBrandLogo(): string {
  const { isDark } = useTheme();
  return isDark ? logoDark : logoLight;
}