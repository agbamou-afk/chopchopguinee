import { useEffect, useState } from "react";
import { Download, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/AuthContext";

const LS_DISMISSED = "cc:install_prompt_dismissed_at";
const LS_OPEN_COUNT = "cc:app_open_count";
const COOLDOWN_DAYS = 7;

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

function shouldShow(profileComplete: boolean): boolean {
  try {
    const dismissed = Number(localStorage.getItem(LS_DISMISSED) ?? "0");
    if (dismissed && Date.now() - dismissed < COOLDOWN_DAYS * 86400_000) return false;
    const opens = Number(localStorage.getItem(LS_OPEN_COUNT) ?? "0");
    return profileComplete || opens >= 2;
  } catch {
    return false;
  }
}

export function InstallPrompt() {
  const { user, profile } = useAuth();
  const [evt, setEvt] = useState<BeforeInstallPromptEvent | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    try {
      const n = Number(localStorage.getItem(LS_OPEN_COUNT) ?? "0") + 1;
      localStorage.setItem(LS_OPEN_COUNT, String(n));
    } catch { /* ignore */ }
  }, []);

  useEffect(() => {
    const handler = (e: Event) => {
      e.preventDefault();
      setEvt(e as BeforeInstallPromptEvent);
      const profileComplete = !!user && !!profile?.full_name;
      if (shouldShow(profileComplete)) setOpen(true);
    };
    window.addEventListener("beforeinstallprompt", handler);
    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, [user, profile]);

  if (!open || !evt) return null;

  const dismiss = () => {
    try { localStorage.setItem(LS_DISMISSED, String(Date.now())); } catch { /* ignore */ }
    setOpen(false);
  };

  const install = async () => {
    try {
      await evt.prompt();
      await evt.userChoice;
    } catch { /* ignore */ }
    setOpen(false);
    setEvt(null);
  };

  return (
    <div className="fixed bottom-20 inset-x-3 z-[55] sm:left-auto sm:right-4 sm:max-w-sm">
      <div className="rounded-2xl bg-card border border-border shadow-elevated p-4 flex items-start gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
          <Download className="w-5 h-5 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-sm">Installer CHOPCHOP</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Installez CHOPCHOP sur votre téléphone pour un accès plus rapide.
          </p>
          <div className="flex gap-2 mt-3">
            <Button size="sm" onClick={install}>Installer</Button>
            <Button size="sm" variant="ghost" onClick={dismiss}>Plus tard</Button>
          </div>
        </div>
        <button
          aria-label="Fermer"
          onClick={dismiss}
          className="text-muted-foreground hover:text-foreground p-1 -m-1"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}