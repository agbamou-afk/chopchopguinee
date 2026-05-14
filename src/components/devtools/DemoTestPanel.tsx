import { useEffect, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { FlaskConical, LogIn, Wallet, Car, Bell, Trash2, RefreshCw, User, ShieldCheck, Send } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { chopToast } from "@/lib/toast";
import { notifications } from "@/lib/notifications";
import { useAuth } from "@/contexts/AuthContext";

const DEMO = {
  client: { email: "demo.client@chopchop.gn", password: "demo1234", label: "Demo Client" },
  driver: { email: "demo.driver@chopchop.gn", password: "demo1234", label: "Demo Chauffeur" },
} as const;

const DEFAULT_TEST_BALANCE = 100_000;

/**
 * Hidden internal E2E test harness for the two demo accounts.
 *
 * Mounted only in DEV, when `?demo=1` is on the URL, or for admin users
 * (see <App />). Provides one-click flows for the two demo accounts:
 *   - quick-login as demo client / driver
 *   - reset active rides (cancel anything in flight)
 *   - reset wallet balance to a known starting amount
 *   - seed a deterministic batch of in-app notifications
 *   - clear local notification state
 *
 * All actions are best-effort: when RLS rejects a write we surface the
 * error via toast so the operator knows the env can't be reset from the
 * client and needs an admin-only path. The panel never blocks normal UX.
 */
export function DemoTestPanel() {
  const { user, isAdmin } = useAuth();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const run = async (key: string, fn: () => Promise<unknown>) => {
    setBusy(key);
    try { await fn(); } finally { setBusy(null); }
  };

  const quickLogin = (which: keyof typeof DEMO) =>
    run(`login:${which}`, async () => {
      await supabase.auth.signOut().catch(() => {});
      const creds = DEMO[which];
      const { error } = await supabase.auth.signInWithPassword({
        email: creds.email,
        password: creds.password,
      });
      if (error) {
        chopToast.error(`Échec ${creds.label}`, { description: error.message });
        return;
      }
      chopToast.success(`Connecté — ${creds.label}`);
      setOpen(false);
    });

  const resetActiveRides = () =>
    run("rides", async () => {
      if (!user) return chopToast.warning("Connecte-toi à un compte démo d'abord.");
      const active = ["requested", "matched", "accepted", "en_route", "arrived", "in_progress"];
      const { data, error } = await supabase
        .from("rides")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .or(`client_id.eq.${user.id},driver_id.eq.${user.id}`)
        .in("status", active as never)
        .select("id");
      if (error) {
        chopToast.error("Reset courses échoué", { description: error.message });
        return;
      }
      chopToast.success(`Courses annulées : ${data?.length ?? 0}`);
    });

  const resetWallet = () =>
    run("wallet", async () => {
      if (!user) return chopToast.warning("Connecte-toi à un compte démo d'abord.");
      const { error } = await supabase
        .from("wallets")
        .update({
          balance_gnf: DEFAULT_TEST_BALANCE,
          held_gnf: 0,
          updated_at: new Date().toISOString(),
        })
        .eq("owner_user_id", user.id);
      if (error) {
        chopToast.error("Reset wallet échoué", { description: error.message });
        return;
      }
      chopToast.success(`Solde remis à ${DEFAULT_TEST_BALANCE.toLocaleString("fr-FR")} GNF`);
    });

  const seedNotifications = () =>
    run("seed", async () => {
      const seeds = [
        { kind: "wallet" as const, title: "Recharge créditée", body: "+50 000 GNF via Orange Money." },
        { kind: "ride" as const, title: "Course terminée", body: "Madina → Kaloum • 12 500 GNF" },
        { kind: "order" as const, title: "Commande livrée", body: "Restaurant Le Damier • 3 articles" },
        { kind: "support" as const, title: "Réponse du support", body: "Votre ticket a été mis à jour." },
        { kind: "marche" as const, title: "Nouveau message", body: "Acheteur intéressé par votre annonce." },
      ];
      for (const s of seeds) notifications.push(s);
      chopToast.success(`${seeds.length} notifications de test ajoutées`);
    });

  const clearNotifications = () =>
    run("clear-notif", async () => {
      notifications.clear();
      chopToast.success("Notifications locales effacées");
    });

  const runIntegrityCheck = () =>
    run("integrity", async () => {
      if (!user) return chopToast.warning("Connecte-toi à un compte démo d'abord.");
      const { data: rides, error: rErr } = await supabase
        .from("rides")
        .select("id, completed_at")
        .or(`client_id.eq.${user.id},driver_id.eq.${user.id}`)
        .eq("status", "completed")
        .order("completed_at", { ascending: false })
        .limit(1);
      if (rErr) return chopToast.error("Lecture courses échouée", { description: rErr.message });
      const ride = rides?.[0];
      if (!ride) return chopToast.warning("Aucune course terminée à vérifier.");
      const { data, error } = await supabase.rpc("ride_integrity_check", { p_ride_id: ride.id });
      if (error) return chopToast.error("Vérification échouée", { description: error.message });
      const report = data as {
        ok: boolean;
        is_demo?: boolean;
        financial_check?: string;
        message?: string;
        checks?: Array<{ name: string; ok: boolean }>;
      } | null;
      const failed = (report?.checks ?? []).filter((c) => !c.ok).map((c) => c.name);
      // eslint-disable-next-line no-console
      console.log("[ride_integrity_check]", report);
      if (report?.ok && report?.is_demo && report?.financial_check === "skipped_demo_no_hold") {
        chopToast.success("Cycle démo OK · règlement ignoré", {
          description:
            report.message ??
            `Course démo ${ride.id.slice(0, 8)} terminée. Aucun hold wallet, règlement financier ignoré.`,
        });
      } else if (report?.ok) {
        chopToast.success("Wallet OK", {
          description: `Course ${ride.id.slice(0, 8)} • toutes les vérifications passent.`,
        });
      } else {
        chopToast.error("Anomalie détectée", {
          description: failed.length ? failed.join(", ") : "Voir console pour le rapport.",
        });
      }
    });

  const sendTestOfferToDemoDriver = () =>
    run("test-offer", async () => {
      const { data, error } = await supabase.rpc("demo_seed_ride_offer" as never);
      if (error) {
        chopToast.error("Envoi demande test échoué", { description: error.message });
        return;
      }
      const id = (data as { offer_id?: string } | null)?.offer_id;
      chopToast.success("Demande test envoyée au chauffeur démo", {
        description: id ? `Offer ${id.slice(0, 8)} • chauffeur réinitialisé • expire dans 30 s` : undefined,
      });
    });

  const resetDemoDriver = () =>
    run("reset-demo-driver", async () => {
      const { data, error } = await supabase.rpc("demo_reset_driver" as never);
      if (error) {
        chopToast.error("Réinitialisation chauffeur échouée", { description: error.message });
        return;
      }
      const result = data as { cancelled_rides?: number; expired_offers?: number } | null;
      chopToast.success("Chauffeur démo remis en ligne", {
        description: `${result?.cancelled_rides ?? 0} course(s) nettoyée(s) • ${result?.expired_offers ?? 0} offre(s) expirée(s)`,
      });
    });

  // Hide entirely if not eligible (extra defence — App.tsx already gates).
  const enabled =
    import.meta.env.DEV ||
    (typeof window !== "undefined" && /[?&]demo=1/.test(window.location.search)) ||
    isAdmin;
  if (!enabled) return null;

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button
          size="icon"
          variant="secondary"
          className="fixed bottom-40 right-4 z-50 rounded-full shadow-lg border border-border"
          aria-label="Panneau de test démo"
        >
          <FlaskConical className="w-5 h-5" />
        </Button>
      </SheetTrigger>
      <SheetContent side="right" className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <FlaskConical className="w-4 h-4 text-primary" /> Démo & E2E
          </SheetTitle>
        </SheetHeader>

        <div className="space-y-4 mt-4 pb-10">
          <Card className="p-3 space-y-1.5 text-sm">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-2"><User className="w-4 h-4" /> Session</span>
              {user ? (
                <Badge variant="secondary" className="font-mono text-[10px] truncate max-w-[180px]">
                  {user.email ?? user.id.slice(0, 8)}
                </Badge>
              ) : (
                <Badge variant="outline">Anonyme</Badge>
              )}
            </div>
          </Card>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
              Connexion rapide
            </h4>
            <div className="grid grid-cols-2 gap-2">
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy}
                onClick={() => quickLogin("client")}
                className="gap-1.5"
              >
                <LogIn className="w-3.5 h-3.5" />
                {busy === "login:client" ? "…" : "Client"}
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy}
                onClick={() => quickLogin("driver")}
                className="gap-1.5"
              >
                <LogIn className="w-3.5 h-3.5" />
                {busy === "login:driver" ? "…" : "Chauffeur"}
              </Button>
            </div>
          </div>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
              Reset état de test
            </h4>
            <div className="space-y-2">
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy || !user}
                onClick={resetActiveRides}
                className="w-full justify-start gap-2"
              >
                <Car className="w-4 h-4" />
                {busy === "rides" ? "Annulation…" : "Annuler courses & commandes actives"}
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy || !user}
                onClick={resetWallet}
                className="w-full justify-start gap-2"
              >
                <Wallet className="w-4 h-4" />
                {busy === "wallet"
                  ? "Reset…"
                  : `Reset wallet → ${DEFAULT_TEST_BALANCE.toLocaleString("fr-FR")} GNF`}
              </Button>
            </div>
            {!user && (
              <p className="text-[11px] text-muted-foreground mt-1.5">
                Connecte-toi à un compte démo pour activer les resets.
              </p>
            )}
          </div>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
              Notifications
            </h4>
            <div className="space-y-2">
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy}
                onClick={seedNotifications}
                className="w-full justify-start gap-2"
              >
                <Bell className="w-4 h-4" />
                {busy === "seed" ? "Ajout…" : "Seeder 5 notifications de test"}
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={!!busy}
                onClick={clearNotifications}
                className="w-full justify-start gap-2"
              >
                <Trash2 className="w-4 h-4" />
                Effacer notifications locales
              </Button>
            </div>
          </div>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
              Intégrité wallet
            </h4>
            <Button
              size="sm"
              variant="outline"
              disabled={!!busy || !user}
              onClick={runIntegrityCheck}
              className="w-full justify-start gap-2"
            >
              <ShieldCheck className="w-4 h-4" />
              {busy === "integrity" ? "Vérification…" : "Vérifier dernière course terminée"}
            </Button>
            <p className="text-[11px] text-muted-foreground mt-1.5">
              Contrôle débit client, crédit chauffeur, commission, ledger, audit & double capture.
            </p>
          </div>

          <div>
            <h4 className="text-xs uppercase tracking-wide text-muted-foreground mb-2">
              Flux courses
            </h4>
            <Button
              size="sm"
              variant="outline"
              disabled={!!busy || !user}
              onClick={resetDemoDriver}
              className="w-full justify-start gap-2 mb-2"
            >
              <RefreshCw className="w-4 h-4" />
              {busy === "reset-demo-driver" ? "Réinitialisation…" : "Réinitialiser le chauffeur démo"}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={!!busy || !user}
              onClick={sendTestOfferToDemoDriver}
              className="w-full justify-start gap-2"
            >
              <Send className="w-4 h-4" />
              {busy === "test-offer" ? "Envoi…" : "Envoyer une demande test au chauffeur démo"}
            </Button>
            <p className="text-[11px] text-muted-foreground mt-1.5">
              Nettoie les courses bloquées, crée une offre pending ciblée sur demo.driver — déclenche le banner global et le bottom sheet.
            </p>
          </div>

          <Button
            size="sm"
            variant="ghost"
            className="w-full gap-2"
            onClick={() => window.location.reload()}
          >
            <RefreshCw className="w-4 h-4" /> Recharger l'app
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}
