import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { readFileSync } from "node:fs";
import { PasswordInput } from "@/components/ui/password-input";

const SHOW = "Afficher le mot de passe";
const HIDE = "Masquer le mot de passe";

function SignInForm({ onSubmit }: { onSubmit: () => void }) {
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit();
      }}
    >
      <label htmlFor="pw">Mot de passe</label>
      <PasswordInput id="pw" autoComplete="current-password" defaultValue="" required />
      <button type="submit">Se connecter</button>
    </form>
  );
}

function SignUpForm() {
  return (
    <form>
      <label htmlFor="pw1">Mot de passe</label>
      <PasswordInput id="pw1" autoComplete="new-password" />
      <label htmlFor="pw2">Confirmer</label>
      <PasswordInput id="pw2" autoComplete="new-password" />
    </form>
  );
}

describe("PasswordInput — visibility UX law", () => {
  it("A. is masked by default and exposes a show control", () => {
    render(<SignInForm onSubmit={() => {}} />);
    const input = screen.getByLabelText("Mot de passe") as HTMLInputElement;
    expect(input.type).toBe("password");
    expect(screen.getByRole("button", { name: SHOW })).toBeTruthy();
  });

  it("B. toggle reveals exactly the typed value without changing it", async () => {
    const user = userEvent.setup();
    render(<SignInForm onSubmit={() => {}} />);
    const input = screen.getByLabelText("Mot de passe") as HTMLInputElement;
    await user.type(input, "  Mot DePasse 123  ");
    const before = input.value;
    await user.click(screen.getByRole("button", { name: SHOW }));
    expect(input.type).toBe("text");
    expect(input.value).toBe(before);
    expect(input.value).toBe("  Mot DePasse 123  ");
  });

  it("C. a second toggle masks it again, value untouched", async () => {
    const user = userEvent.setup();
    render(<SignInForm onSubmit={() => {}} />);
    const input = screen.getByLabelText("Mot de passe") as HTMLInputElement;
    await user.type(input, "secret42");
    await user.click(screen.getByRole("button", { name: SHOW }));
    await user.click(screen.getByRole("button", { name: HIDE }));
    expect(input.type).toBe("password");
    expect(input.value).toBe("secret42");
  });

  it("D. the toggle button does not submit the form", async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();
    render(<SignInForm onSubmit={onSubmit} />);
    const btn = screen.getByRole("button", { name: SHOW });
    expect(btn.getAttribute("type")).toBe("button");
    await user.click(btn);
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("D2. the toggle is keyboard operable", async () => {
    const user = userEvent.setup();
    render(<SignInForm onSubmit={() => {}} />);
    const input = screen.getByLabelText("Mot de passe") as HTMLInputElement;
    input.focus();
    await user.tab();
    expect(document.activeElement).toBe(screen.getByRole("button", { name: SHOW }));
    await user.keyboard("{Enter}");
    expect(input.type).toBe("text");
  });

  it("E. password and confirm-password toggles are independent", async () => {
    const user = userEvent.setup();
    render(<SignUpForm />);
    const pw1 = screen.getByLabelText("Mot de passe") as HTMLInputElement;
    const pw2 = screen.getByLabelText("Confirmer") as HTMLInputElement;
    const [t1, t2] = screen.getAllByRole("button", { name: SHOW });
    await user.click(t1);
    expect(pw1.type).toBe("text");
    expect(pw2.type).toBe("password");
    await user.click(t2);
    expect(pw1.type).toBe("text");
    expect(pw2.type).toBe("text");
  });

  it("G. aria label and pressed state track visibility", async () => {
    const user = userEvent.setup();
    render(<SignInForm onSubmit={() => {}} />);
    const btn = screen.getByRole("button", { name: SHOW });
    expect(btn.getAttribute("aria-pressed")).toBe("false");
    await user.click(btn);
    const hideBtn = screen.getByRole("button", { name: HIDE });
    expect(hideBtn.getAttribute("aria-pressed")).toBe("true");
  });

  it("H. autocomplete semantics are preserved through the toggle", async () => {
    const user = userEvent.setup();
    render(<SignUpForm />);
    const pw1 = screen.getByLabelText("Mot de passe") as HTMLInputElement;
    expect(pw1.getAttribute("autocomplete")).toBe("new-password");
    await user.click(screen.getAllByRole("button", { name: SHOW })[0]);
    expect(pw1.getAttribute("autocomplete")).toBe("new-password");
  });

  it("I. visibility state is never persisted to storage", async () => {
    const user = userEvent.setup();
    const ls = vi.spyOn(Storage.prototype, "setItem");
    render(<SignInForm onSubmit={() => {}} />);
    await user.click(screen.getByRole("button", { name: SHOW }));
    expect(ls).not.toHaveBeenCalled();
    ls.mockRestore();
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
  });

  it("I2. remounting resets visibility to hidden", async () => {
    const user = userEvent.setup();
    const { unmount } = render(<SignInForm onSubmit={() => {}} />);
    await user.click(screen.getByRole("button", { name: SHOW }));
    unmount();
    render(<SignInForm onSubmit={() => {}} />);
    expect((screen.getByLabelText("Mot de passe") as HTMLInputElement).type).toBe("password");
  });
});

describe("F. every auth credential screen uses the shared control", () => {
  const screens = [
    "src/pages/Auth.tsx",
    "src/pages/ForgotPassword.tsx",
    "src/pages/AccountSecurity.tsx",
    "src/pages/ProfileInfo.tsx",
    "src/pages/admin/AdminChangePassword.tsx",
    "src/components/recovery/RecoverySetupWizard.tsx",
  ];

  it.each(screens)("%s uses PasswordInput and no raw password input", (file) => {
    const src = readFileSync(file, "utf8");
    expect(src).toContain("<PasswordInput");
    expect(src).not.toContain('type="password"');
  });

  it("H2. keeps current-password / new-password autocomplete semantics", () => {
    expect(readFileSync("src/pages/Auth.tsx", "utf8")).toContain("current-password");
    expect(readFileSync("src/pages/ForgotPassword.tsx", "utf8")).toContain("new-password");
    expect(readFileSync("src/pages/AccountSecurity.tsx", "utf8")).toContain("current-password");
  });
});
