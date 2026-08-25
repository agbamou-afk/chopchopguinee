import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { EtaPricePreview, type PreviewState } from "@/components/booking/EtaPricePreview";

/**
 * Failure-domain separation: a fare failure, a routing failure and a
 * signed-out session must each produce their own copy. Regression guard for
 * the "Aucun itinéraire trouvé" message shown on fare/auth failures.
 */
function renderState(state: PreviewState) {
  return render(<EtaPricePreview state={state} serviceType="moto" onRetry={() => {}} onSignIn={() => {}} />);
}

describe("EtaPricePreview failure domains", () => {
  it("route failure reports the itinerary, not the fare", () => {
    renderState("route-unavailable");
    expect(screen.getByText(/Aucun itinéraire trouvé/)).toBeInTheDocument();
    expect(screen.queryByText(/Tarif indisponible pour le moment/)).toBeNull();
  });

  it("fare failure never claims the itinerary failed", () => {
    renderState("fare-unavailable");
    expect(screen.getByText(/Tarif indisponible pour le moment/)).toBeInTheDocument();
    expect(screen.queryByText(/Aucun itinéraire trouvé/)).toBeNull();
  });

  it("signed-out state asks for sign-in instead of an error", () => {
    renderState("auth-required");
    expect(screen.getByText(/Connectez-vous pour voir le prix/)).toBeInTheDocument();
    expect(screen.getByText("Se connecter")).toBeInTheDocument();
    expect(screen.queryByText(/Aucun itinéraire trouvé/)).toBeNull();
  });

  it("network state stays distinct from both", () => {
    renderState("network");
    expect(screen.getByText(/Connexion instable/)).toBeInTheDocument();
  });

  it("idle and ready show no failure banner", () => {
    const { unmount } = renderState("idle");
    expect(screen.queryByTestId("preview-route-unavailable")).toBeNull();
    expect(screen.queryByTestId("preview-auth-required")).toBeNull();
    unmount();
    renderState("calculating");
    expect(screen.queryByTestId("preview-fare-unavailable")).toBeNull();
  });
});
