import { toast as sonnerToast } from "sonner";
import type { ExternalToast } from "sonner";

/**
 * Unified CHOP CHOP feedback toasts.
 *
 * Variants share consistent timing, spacing, and mobile positioning
 * (configured globally on <Sonner /> in src/components/ui/sonner.tsx).
 *
 * Use `chopToast.success/warning/error/info(title, opts)` everywhere so
 * notifications feel coherent across the app.
 */

const DURATIONS = {
  success: 3500,
  info: 4000,
  warning: 5000,
  error: 6000,
} as const;

type Opts = Omit<ExternalToast, "duration"> & { duration?: number };

function build(variant: keyof typeof DURATIONS, message: string, opts?: Opts) {
  return { duration: DURATIONS[variant], ...opts };
}

export const chopToast = {
  success: (message: string, opts?: Opts) =>
    sonnerToast.success(message, build("success", message, opts)),
  warning: (message: string, opts?: Opts) =>
    sonnerToast.warning(message, build("warning", message, opts)),
  error: (message: string, opts?: Opts) =>
    sonnerToast.error(message, build("error", message, opts)),
  info: (message: string, opts?: Opts) =>
    sonnerToast.info(message, build("info", message, opts)),
  message: (message: string, opts?: Opts) =>
    sonnerToast(message, build("info", message, opts)),
  dismiss: sonnerToast.dismiss,
  promise: sonnerToast.promise,
};

export type ChopToast = typeof chopToast;
