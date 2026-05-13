import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Routes, Route } from "react-router-dom";
import { profileComplete, AuthProvider, useAuth, type ProfileRecord } from "@/contexts/AuthContext";
import { can, PERMISSIONS } from "@/lib/admin/permissions";

// ── Mock the Supabase client used by AuthContext ──────────────────────────────

let mockSession: { user: { id: string; email: string | null; phone: string | null } } | null = null;
let mockProfile: Partial<ProfileRecord> | null = null;
let mockRoles: { role: string }[] = [];
const authListeners: Array<(event: string, session: typeof mockSession) => void> = [];

vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    auth: {
      getSession: () => Promise.resolve({ data: { session: mockSession } }),
      onAuthStateChange: (cb: (event: string, session: typeof mockSession) => void) => {
        authListeners.push(cb);
        return { data: { subscription: { unsubscribe: () => {} } } };
      },
      signOut: () => {
        mockSession = null;
        authListeners.forEach((cb) => cb("SIGNED_OUT", null));
        return Promise.resolve({ error: null });
      },
    },
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () =>
            Promise.resolve({
              data: table === "profiles" ? mockProfile : null,
              error: null,
            }),
        }),
        // For user_roles list query
        ...(table === "user_roles"
          ? {
              eq: () => Promise.resolve({ data: mockRoles, error: null }),
            }
          : {}),
      }),
    }),
  },
}));

function reset() {
  mockSession = null;
  mockProfile = null;
  mockRoles = [];
  authListeners.length = 0;
}

// ── profileComplete unit tests ────────────────────────────────────────────────

describe("profileComplete", () => {
  it("returns false when null", () => {
    expect(profileComplete(null)).toBe(false);
  });
  it("returns false if any of first/last/phone missing", () => {
    expect(
      profileComplete({
        user_id: "u",
        first_name: "Alpha",
        last_name: null,
        phone: "+22461",
        display_name: null,
        full_name: null,
        email: null,
        avatar_url: null,
        account_status: "active",
      }),
    ).toBe(false);
  });
  it("returns true when all required fields present", () => {
    expect(
      profileComplete({
        user_id: "u",
        first_name: "Alpha",
        last_name: "Diallo",
        phone: "+224611111111",
        display_name: null,
        full_name: null,
        email: null,
        avatar_url: null,
        account_status: "active",
      }),
    ).toBe(true);
  });
});

// ── permissions / can() ───────────────────────────────────────────────────────

describe("admin permissions", () => {
  it("god_admin has access to every module", () => {
    Object.keys(PERMISSIONS.god_admin).forEach((m) => {
      expect(can("god_admin", m as never, "view")).toBe(true);
      expect(can("god_admin", m as never, "delete")).toBe(true);
    });
  });
  it("operations_admin cannot access wallet edit", () => {
    expect(can("operations_admin", "wallet", "edit")).toBe(false);
  });
  it("finance_admin can approve vendor changes", () => {
    expect(can("finance_admin", "vendors", "approve")).toBe(true);
  });
  it("null role is rejected", () => {
    expect(can(null, "dashboard", "view")).toBe(false);
  });
});

// ── AuthProvider integration with mocked supabase ─────────────────────────────

function Probe() {
  const a = useAuth();
  if (!a.ready) return <span>loading</span>;
  return (
    <div>
      <span data-testid="logged">{String(a.isLoggedIn)}</span>
      <span data-testid="admin">{String(a.isAdmin)}</span>
      <span data-testid="god">{String(a.isGodAdmin)}</span>
      <span data-testid="complete">{String(a.isProfileComplete)}</span>
    </div>
  );
}

function renderApp() {
  return render(
    <MemoryRouter>
      <AuthProvider>
        <Routes>
          <Route path="/" element={<Probe />} />
        </Routes>
      </AuthProvider>
    </MemoryRouter>,
  );
}

describe("AuthProvider", () => {
  beforeEach(() => reset());

  it("reports logged-out state when no session", async () => {
    renderApp();
    await waitFor(() => expect(screen.getByTestId("logged").textContent).toBe("false"));
    expect(screen.getByTestId("admin").textContent).toBe("false");
  });

  it("loads profile + roles for an admin session and flags isAdmin / isGodAdmin", async () => {
    mockSession = { user: { id: "u1", email: null, phone: "+224611" } };
    mockProfile = {
      user_id: "u1",
      first_name: "Alpha",
      last_name: "Admin",
      phone: "+224611",
      email: null,
      display_name: "Alpha Admin",
      full_name: "Alpha Admin",
      avatar_url: null,
      account_status: "active",
    };
    mockRoles = [{ role: "client" }, { role: "god_admin" }];
    renderApp();
    await waitFor(() => expect(screen.getByTestId("logged").textContent).toBe("true"));
    await waitFor(() => expect(screen.getByTestId("god").textContent).toBe("true"));
    expect(screen.getByTestId("admin").textContent).toBe("true");
    expect(screen.getByTestId("complete").textContent).toBe("true");
  });

  it("regular client is logged in but not admin", async () => {
    mockSession = { user: { id: "u2", email: null, phone: "+224622" } };
    mockProfile = {
      user_id: "u2",
      first_name: "Bob",
      last_name: "Client",
      phone: "+224622",
      email: null,
      display_name: "Bob",
      full_name: "Bob Client",
      avatar_url: null,
      account_status: "active",
    };
    mockRoles = [{ role: "client" }];
    renderApp();
    await waitFor(() => expect(screen.getByTestId("logged").textContent).toBe("true"));
    expect(screen.getByTestId("admin").textContent).toBe("false");
    expect(screen.getByTestId("god").textContent).toBe("false");
  });

  it("flags incomplete profile when first/last/phone missing", async () => {
    mockSession = { user: { id: "u3", email: null, phone: null } };
    mockProfile = {
      user_id: "u3",
      first_name: null,
      last_name: null,
      phone: null,
      email: null,
      display_name: null,
      full_name: null,
      avatar_url: null,
      account_status: "active",
    };
    mockRoles = [{ role: "client" }];
    renderApp();
    await waitFor(() => expect(screen.getByTestId("logged").textContent).toBe("true"));
    expect(screen.getByTestId("complete").textContent).toBe("false");
  });
});