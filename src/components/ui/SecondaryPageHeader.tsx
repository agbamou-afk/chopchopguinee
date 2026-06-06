import { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft } from "lucide-react";

interface SecondaryPageHeaderProps {
  title: string;
  subtitle?: string;
  showBack?: boolean;
  onBack?: () => void;
  rightAction?: ReactNode;
}

/**
 * Standardized header for secondary / account / settings / legal pages.
 * Clean layout: back arrow + title (no logo, no clutter).
 * Safe-area aware. Use across Profile, Legal, Privacy, Permissions, Help, etc.
 */
export function SecondaryPageHeader({
  title,
  subtitle,
  showBack = true,
  onBack,
  rightAction,
}: SecondaryPageHeaderProps) {
  const navigate = useNavigate();
  const handleBack = () => {
    if (onBack) onBack();
    else navigate(-1);
  };

  return (
    <header
      className="gradient-primary text-primary-foreground rounded-b-3xl px-5 pb-8"
      style={{ paddingTop: "max(1.5rem, env(safe-area-inset-top) + 0.5rem)" }}
    >
      <div className="flex items-center gap-4 max-w-2xl mx-auto">
        {showBack && (
          <button
            onClick={handleBack}
            className="shrink-0 p-2.5 rounded-full hover:bg-white/10 transition-colors"
            aria-label="Retour"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
        )}
        <div className="min-w-0 flex-1">
          <h1 className="text-xl font-bold tracking-tight truncate">{title}</h1>
          {subtitle && (
            <p className="text-xs text-primary-foreground/80 mt-0.5 truncate">{subtitle}</p>
          )}
        </div>
        {rightAction && <div className="shrink-0">{rightAction}</div>}
      </div>
    </header>
  );
}

export default SecondaryPageHeader;