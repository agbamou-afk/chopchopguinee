import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";

/**
 * Identity-safety proof for the shared module-level recovery-status store.
 * No status belonging to one authenticated UUID may ever be observed as the
 * status of another UUID, and no in-flight fetch may publish after sign-out
 * or after an account switch.
 */

const auth: { ready: boolean; isLoggedIn: boolean; user: { id: string } | null } = {
  ready: true,
  isLoggedIn: true,
  user: { id: "user-a" },
};
vi.mock("@/contexts/AuthContext", () => ({ useAuth: () => auth }));

type Status = { configured: boolean; question_ids: string[] } | null;
let resolvers: Array<(v: Status) => void> = [];
let auto: Status | undefined;
const fetchRecoveryStatus = vi.fn(
  () =>
    new Promise<Status>((resolve) => {
      if (auto !== undefined) resolve(auto);
      else resolvers.push(resolve);
    }),
);
vi.mock("@/lib/recovery/api", () => ({
  fetchRecoveryStatus: () => fetchRecoveryStatus(),
}));

import { useRecoveryStatus, resetRecoveryStatus } from "@/hooks/useRecoveryStatus";

const CONFIGURED = { configured: true, question_ids: ["q1", "q2", "q3"] };
const NOT_CONFIGURED = { configured: false, question_ids: [] };

function Probe() {
  const { configured, loading, status } = useRecoveryStatus();
  return (
    <div>
      <span data-testid="configured">{String(configured)}</span>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="qids">{(status?.question_ids ?? []).join(",")}</span>
    </div>
  );
}

const read = (id: string) => screen.getByTestId(id).textContent;
const flush = () => act(async () => { await Promise.resolve(); await Promise.resolve(); });

beforeEach(() => {
  resolvers = [];
  auto = undefined;
  fetchRecoveryStatus.mockClear();
  auth.isLoggedIn = true;
  auth.user = { id: "user-a" };
  resetRecoveryStatus();
});

describe("recovery status store — identity scoping", () => {
  it("A configured=true → switch to B while logged in → B never inherits A's status", async () => {
    auto = CONFIGURED;
    const { rerender } = render(<Probe />);
    await flush();
    expect(read("configured")).toBe("true");
    expect(read("qids")).toBe("q1,q2,q3");

    // Direct account switch, still logged in. B's fetch is slow.
    auto = undefined;
    auth.user = { id: "user-b" };
    rerender(<Probe />);
    expect(read("configured")).toBe("false");
    expect(read("qids")).toBe("");
    expect(read("loading")).toBe("true");

    await act(async () => { resolvers.shift()?.(NOT_CONFIGURED); });
    expect(read("configured")).toBe("false");
    expect(read("loading")).toBe("false");
  });

  it("in-flight for A → sign out/reset → late A response cannot repopulate", async () => {
    render(<Probe />);
    await flush();
    expect(read("loading")).toBe("true");

    act(() => { resetRecoveryStatus(); });
    await act(async () => { resolvers.shift()?.(CONFIGURED); });

    expect(read("configured")).toBe("false");
    expect(read("qids")).toBe("");
  });

  it("in-flight for A → switch to B → late A response cannot overwrite B", async () => {
    const { rerender } = render(<Probe />);
    await flush();

    auth.user = { id: "user-b" };
    rerender(<Probe />);
    await flush();

    const aResolve = resolvers.shift()!;
    const bResolve = resolvers.shift()!;
    await act(async () => { bResolve(NOT_CONFIGURED); });
    await act(async () => { aResolve(CONFIGURED); });

    expect(read("configured")).toBe("false");
    expect(read("qids")).toBe("");
  });

  it("forced revalidation during a slow initial request publishes only the forced result", async () => {
    let hook: ReturnType<typeof useRecoveryStatus> | null = null;
    function Cap() {
      hook = useRecoveryStatus();
      return <Probe />;
    }
    render(<Cap />);
    await flush();

    let forced: Status | undefined;
    await act(async () => {
      const p = hook!.reload(true).then((r) => { forced = r as Status; });
      // Initial (stale) request resolves late with the pre-enrollment value.
      resolvers.shift()?.(NOT_CONFIGURED);
      resolvers.shift()?.(CONFIGURED);
      await p;
    });

    expect(forced).toEqual(CONFIGURED);
    expect(read("configured")).toBe("true");
  });

  it("never persists recovery status to storage", async () => {
    auto = CONFIGURED;
    render(<Probe />);
    await flush();
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
  });
});
