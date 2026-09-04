import * as React from "react";
import { Eye, EyeOff } from "lucide-react";

import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

export const SHOW_PASSWORD_LABEL = "Afficher le mot de passe";
export const HIDE_PASSWORD_LABEL = "Masquer le mot de passe";

type PasswordInputProps = Omit<React.ComponentProps<"input">, "type">;

/**
 * Password field with an integrated show/hide control.
 *
 * - Hidden by default; visibility lives in local component state only and is
 *   never persisted (no localStorage / sessionStorage).
 * - Toggling only swaps the input `type`; the value is never read, rewritten
 *   or trimmed here.
 */
const PasswordInput = React.forwardRef<HTMLInputElement, PasswordInputProps>(
  ({ className, ...props }, ref) => {
    const [visible, setVisible] = React.useState(false);

    return (
      <div className="relative">
        <Input
          {...props}
          ref={ref}
          type={visible ? "text" : "password"}
          className={cn("pr-11", className)}
        />
        <button
          type="button"
          onClick={() => setVisible((v) => !v)}
          aria-label={visible ? HIDE_PASSWORD_LABEL : SHOW_PASSWORD_LABEL}
          aria-pressed={visible}
          tabIndex={props.disabled ? -1 : 0}
          disabled={props.disabled}
          className="absolute inset-y-0 right-0 flex h-full w-11 items-center justify-center rounded-r-md text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50"
        >
          {visible ? (
            <EyeOff className="h-4 w-4" aria-hidden="true" />
          ) : (
            <Eye className="h-4 w-4" aria-hidden="true" />
          )}
        </button>
      </div>
    );
  },
);
PasswordInput.displayName = "PasswordInput";

export { PasswordInput };
