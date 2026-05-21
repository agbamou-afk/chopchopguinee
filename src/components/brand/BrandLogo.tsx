import logoLight from "@/assets/logo.png";
import logoDark from "@/assets/logo-dark.png";
import { useTheme } from "@/hooks/useTheme";

type Props = React.ImgHTMLAttributes<HTMLImageElement> & {
  /** Force a specific variant regardless of current theme. */
  variant?: "auto" | "light" | "dark";
};

export function BrandLogo({ variant = "auto", alt = "WONGO", ...rest }: Props) {
  const { isDark } = useTheme();
  const src =
    variant === "dark" ? logoDark : variant === "light" ? logoLight : isDark ? logoDark : logoLight;
  return <img src={src} alt={alt} {...rest} />;
}

export function useBrandLogo(): string {
  const { isDark } = useTheme();
  return isDark ? logoDark : logoLight;
}