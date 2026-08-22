import type { ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { useServiceExposure } from "@/lib/services/serviceExposure";

interface Props {
  /** Canonical exposure action id (e.g. `merchant`, `driver`, `parcel`). */
  action: string;
  /** Safe destination when the product is not exposed. */
  redirectTo?: string;
  children: ReactNode;
}

/**
 * PASS 2 — direct/deep-link guard. A route that exposes a top-level product
 * whose exposure flag is OFF must not render; it quietly redirects home.
 *
 * The verdict waits for flag readiness (no flash, no redirect loop), and the
 * redirect target is never itself guarded by the same flag.
 */
export function ExposureRouteGuard({ action, redirectTo = "/", children }: Props) {
  const exposure = useServiceExposure();
  if (!exposure.ready) return null;
  if (!exposure.isExposed(action)) return <Navigate to={redirectTo} replace />;
  return <>{children}</>;
}
