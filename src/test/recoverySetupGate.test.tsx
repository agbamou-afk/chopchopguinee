import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Routes, Route, useLocation } from "react-router-dom";

/**
 * Regression proof for the "recovery setup loops / resets after success" defect.
 *
 * Root cause under test: the global gate and the setup page each owned a
 * separate recovery-status instance, so navigation happened on a discarded
 * refresh while the gate still held a stale `configured=false`.
 */

// ── Auth: signed-in, complete profile, non-admin ─────────────────────────────
const auth = {
  ready: true,
  isLoggedIn: true,
  isProfileComplete: true,
  profileLoading: false,
  isAdmin: false,
};
vi.mock("@/contexts/AuthContext", () => ({ useAuth: () => auth }));

// ── Recovery status RPC ──────────────────────────────────────────────────────
let statusQueue: Array<{ configured: boolean; question_ids: string[] } | null> = [];
let statusDelay = 0;
const fetchRecoveryStatus = vi.fn(async () => {
  if (statusDelay) await new Promise((r) => setTimeout(r, statusDelay));
  return statusQueue.length > 1 ? statusQueue.shift()! : statusQueue[0] ?? null;
});
vi.mock("@/lib/recovery/api", () => ({
  fetchRecoveryStatus: (...a: unknown[]) => fetchRecoveryStatus(...(a as [])),
}));

// ── Wizard stub: fires onComplete like a successful enroll_confirm ───────────
vi.mock("@/components/recovery/RecoverySetupWizard", () => ({
  RecoverySetupWizard: ({ onComplete }: { onComplete: () => void }) => (
    <button type="button" onClick={onComplete}>
      stub-confirm
    </button>
  ),
}));
vi.mock("@/components/brand/BrandLogo", () => ({ BrandLogo: () => <div /> }));
vi.mock("@/components/Seo", () => ({ Seo: () => null }));

import RecoverySetup from "@/pages/RecoverySetup";
import { RecoverySetupRedirect } from "@/components/auth/RecoverySetupRedirect";
import { resetRecoveryStatus } from "@/hooks/useRecoveryStatus";

const visits: string[] = [];
function Probe({ label }: { label: string }) {
  const loc = useLocation();
  visits.push(`${label}:${loc.pathname}`);
  return <div>{label}</div>;
}

function renderApp(entry: string) {
  return render(
    <MemoryRouter initialEntries={[entry]}>
      <RecoverySetupRedirect />
      <Routes>
        <Route path="/account/recovery-setup" element={<RecoverySetup />} />
        <Route path="/merchant/hub" element={<Probe label="hub" />} />
        <Route path="/driver/apply" element={<Probe label="apply" />} />
        <Route path="/" element={<Probe label="home" />} />
      </Routes>
    </MemoryRouter>,
  );
}

const NOT_CONFIGURED = { configured: false, question_ids: [] };
const CONFIGURED = { configured: true, question_ids: ["q1", "q2", "q3"] };

beforeEach(() => {
  visits.length = 0;
  statusDelay = 0;
  fetchRecoveryStatus.mockClear();
  resetRecoveryStatus();
});

describe("recovery setup gate", () => {
  it("1. confirm success → exactly one navigation to next, no bounce back", async () => {
    statusQueue = [NOT_CONFIGURED, CONFIGURED];
    renderApp("/account/recovery-setup?next=%2Fmerchant%2Fhub");
    await screen.findByText("stub-confirm");
    await userEvent.click(screen.getByText("stub-confirm"));
    await screen.findByText("hub");
    await new Promise((r) => setTimeout(r, 30));
    expect(visits.filter((v) => v === "hub:/merchant/hub")).toHaveLength(1);
    expect(screen.queryByText("stub-confirm")).toBeNull();
  });

  it("2. slow status → deterministic finalizing state, no reset, no premature nav", async () => {
    statusQueue = [NOT_CONFIGURED, CONFIGURED];
    statusDelay = 60;
    renderApp("/account/recovery-setup?next=%2Fmerchant%2Fhub");
    await screen.findByText("stub-confirm");
    await userEvent.click(screen.getByText("stub-confirm"));
    expect(await screen.findByText(/Finalisation/)).toBeInTheDocument();
    expect(screen.queryByText("stub-confirm")).toBeNull();
    expect(visits).toHaveLength(0);
    await screen.findByText("hub", undefined, { timeout: 2000 });
  });

  it("3. fresh status still false → stays with retry, never navigates", async () => {
    statusQueue = [NOT_CONFIGURED];
    renderApp("/account/recovery-setup?next=%2Fmerchant%2Fhub");
    await screen.findByText("stub-confirm");
    await userEvent.click(screen.getByText("stub-confirm"));
    expect(await screen.findByText("Réessayer")).toBeInTheDocument();
    expect(visits).toHaveLength(0);
  });

  it("4. null/offline status → fail-open, no navigation loop", async () => {
    statusQueue = [null];
    renderApp("/account/recovery-setup?next=%2F");
    await screen.findByText("stub-confirm");
    await new Promise((r) => setTimeout(r, 50));
    // Global gate must not bounce on unknown status, page must not navigate.
    expect(visits).toHaveLength(0);
    expect(screen.getByText("stub-confirm")).toBeInTheDocument();
  });

  it("5. already-configured user redirects once to next", async () => {
    statusQueue = [CONFIGURED];
    renderApp("/account/recovery-setup?next=%2Fmerchant%2Fhub");
    await screen.findByText("hub");
    await new Promise((r) => setTimeout(r, 30));
    expect(visits.filter((v) => v === "hub:/merchant/hub")).toHaveLength(1);
  });

  it("6. generic target path (driver lane) behaves identically", async () => {
    statusQueue = [NOT_CONFIGURED, CONFIGURED];
    renderApp("/account/recovery-setup?next=%2Fdriver%2Fapply");
    await screen.findByText("stub-confirm");
    await userEvent.click(screen.getByText("stub-confirm"));
    await screen.findByText("apply");
    expect(visits.filter((v) => v === "apply:/driver/apply")).toHaveLength(1);
  });

  it("7. unsafe next is ignored and falls back to /", async () => {
    statusQueue = [CONFIGURED];
    renderApp("/account/recovery-setup?next=https%3A%2F%2Fevil.example");
    await screen.findByText("home");
  });
});
