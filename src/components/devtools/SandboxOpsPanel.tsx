import { useEffect, useMemo, useState } from "react";
import { Beaker, Play, Trash2, Activity } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { useAuth } from "@/contexts/AuthContext";
import { isSandboxMode } from "@/lib/runtimeMode";
import { sandboxEngine, SANDBOX_SCENARIOS, type SandboxSnapshot } from "@/lib/sandbox";

/**
 * Sandbox Operational Testing panel.
 *
 * Internal devtool only. Mounted alongside the other devtools when the
 * runtime resolves to `sandbox` (?sandbox=1 / ?debug=1 / DEV) or the
 * signed-in user is an admin. Never visible to public/live users.
 *
 * Drives the in-memory sandbox engine — does NOT touch Supabase,
 * realtime channels, live wallets, or dispatch.
 */
export function SandboxOpsPanel() {
  const { isAdmin } = useAuth();
  const [open, setOpen] = useState(false);
  const [snap, setSnap] = useState<SandboxSnapshot>(() => sandboxEngine.snapshot());
  const [busy, setBusy] = useState<string | null>(null);
  const [familyFilter, setFamilyFilter] = useState<string>("all");

  useEffect(() => sandboxEngine.subscribe(setSnap), []);

  const scenarios = useMemo(
    () => (familyFilter === "all" ? SANDBOX_SCENARIOS : SANDBOX_SCENARIOS.filter((s) => s.family === familyFilter)),
    [familyFilter],
  );

  if (typeof window === "undefined") return null;
  if (!isSandboxMode() && !isAdmin) return null;

  const run = async (id: string) => {
    const sc = SANDBOX_SCENARIOS.find((s) => s.id === id);
    if (!sc) return;
    setBusy(id);
    try { await sandboxEngine.runScenario(sc); } finally { setBusy(null); }
  };

  const activeMissions = snap.missions.filter((m) => !["completed", "cancelled", "failed", "timeout"].includes(m.state));
  const totalWallet = snap.wallet.reduce((acc, w) => acc + w.amountGnf, 0);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button
          size="icon"
          variant="secondary"
          className="fixed bottom-72 right-4 z-50 rounded-full shadow-lg border border-border"
          aria-label="Sandbox Operational Testing"
        >
          <Beaker className="w-5 h-5" />
          {snap.runningScenarios.length > 0 && (
            <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-primary animate-pulse" />
          )}
        </Button>
      </SheetTrigger>
      <SheetContent side="right" className="w-full sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <Beaker className="w-4 h-4 text-primary" /> Sandbox Ops
            <Badge variant="outline" className="ml-auto text-[10px]">isolated · in-memory</Badge>
          </SheetTitle>
        </SheetHeader>

        <div className="grid grid-cols-3 gap-2 mt-4">
          <Card className="p-2 text-center">
            <div className="text-[10px] text-muted-foreground uppercase">Actors</div>
            <div className="text-lg font-semibold">{snap.actors.length}</div>
          </Card>
          <Card className="p-2 text-center">
            <div className="text-[10px] text-muted-foreground uppercase">Missions</div>
            <div className="text-lg font-semibold">{activeMissions.length}<span className="text-xs text-muted-foreground">/{snap.missions.length}</span></div>
          </Card>
          <Card className="p-2 text-center">
            <div className="text-[10px] text-muted-foreground uppercase">Wallet Δ</div>
            <div className="text-sm font-mono">{totalWallet.toLocaleString("fr-FR")}</div>
          </Card>
        </div>

        <Tabs defaultValue="scenarios" className="mt-4">
          <TabsList className="grid w-full grid-cols-5">
            <TabsTrigger value="scenarios">Scénarios</TabsTrigger>
            <TabsTrigger value="runs">Runs</TabsTrigger>
            <TabsTrigger value="missions">Missions</TabsTrigger>
            <TabsTrigger value="wallet">Wallet</TabsTrigger>
            <TabsTrigger value="events">Events</TabsTrigger>
          </TabsList>

          <TabsContent value="scenarios" className="space-y-2 mt-3">
            <div className="flex flex-wrap gap-1.5">
              {["all", "ride", "repas", "marche", "wallet", "failure", "notification", "merchant"].map((f) => (
                <Badge
                  key={f}
                  variant={familyFilter === f ? "default" : "outline"}
                  className="cursor-pointer text-[10px]"
                  onClick={() => setFamilyFilter(f)}
                >
                  {f}
                </Badge>
              ))}
            </div>
            {scenarios.map((s) => (
              <Card key={s.id} className="p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-sm font-medium truncate">{s.title}</div>
                    <div className="text-[11px] text-muted-foreground">{s.description}</div>
                    <div className="text-[10px] text-muted-foreground mt-1 uppercase tracking-wide">{s.family}</div>
                  </div>
                  <Button size="sm" variant="outline" disabled={!!busy} onClick={() => run(s.id)} className="gap-1.5 shrink-0">
                    <Play className="w-3.5 h-3.5" />
                    {busy === s.id ? "…" : "Run"}
                  </Button>
                </div>
              </Card>
            ))}
          </TabsContent>

          <TabsContent value="runs" className="space-y-2 mt-3">
            {snap.runs.length === 0 && <p className="text-xs text-muted-foreground">Aucun run lancé.</p>}
            {snap.runs.map((r) => {
              const variant =
                r.status === "completed" ? "default" :
                r.status === "failed" || r.status === "cancelled" ? "destructive" : "secondary";
              const healthVariant =
                r.health === "pass" ? "default" :
                r.health === "warn" ? "secondary" :
                r.health === "fail" ? "destructive" : "outline";
              const healthClass =
                r.health === "warn" ? "bg-yellow-500/15 text-yellow-700 dark:text-yellow-400 border-yellow-500/40" : "";
              return (
                <Card key={r.id} className="p-2.5">
                  <div className="flex items-center justify-between gap-2">
                    <div className="text-xs font-medium truncate">{r.title}</div>
                    <div className="flex items-center gap-1 shrink-0">
                      {r.health && (
                        <Badge variant={healthVariant} className={`text-[9px] uppercase ${healthClass}`}>
                          {r.health}
                        </Badge>
                      )}
                      <Badge variant={variant} className="text-[9px]">{r.status}</Badge>
                    </div>
                  </div>
                  <div className="mt-1 grid grid-cols-5 gap-1 text-[10px] text-muted-foreground">
                    <span>👤 {r.counts.actors}</span>
                    <span>🎯 {r.counts.missions}</span>
                    <span>💰 {r.counts.wallet}</span>
                    <span>🔔 {r.counts.notifications}</span>
                    <span>⚠ {r.counts.failures}</span>
                  </div>
                  <div className="text-[10px] text-muted-foreground mt-1 font-mono">
                    {r.durationMs != null ? `${r.durationMs} ms` : "…"}
                    {r.error ? ` · ${r.error}` : ""}
                  </div>
                  {r.assertions && r.assertions.length > 0 && (
                    <div className="mt-1.5 space-y-0.5">
                      {r.assertions.map((a, i) => (
                        <div key={i} className="flex items-start gap-1 text-[10px]">
                          <span className={a.ok ? "text-primary" : a.severity === "fail" ? "text-destructive" : "text-yellow-600 dark:text-yellow-400"}>
                            {a.ok ? "✓" : a.severity === "fail" ? "✗" : "⚠"}
                          </span>
                          <span className="text-muted-foreground">{a.label}</span>
                          {a.detail && !a.ok && <span className="text-muted-foreground/70">· {a.detail}</span>}
                        </div>
                      ))}
                    </div>
                  )}
                </Card>
              );
            })}
          </TabsContent>

          <TabsContent value="missions" className="space-y-2 mt-3">
            {snap.missions.length === 0 && <p className="text-xs text-muted-foreground">Aucune mission synthétique.</p>}
            {snap.missions.slice(0, 30).map((m) => (
              <div key={m.id} className="flex items-center justify-between gap-2 text-[11px] border border-border rounded-md px-2 py-1.5">
                <span className="font-mono truncate">{m.kind}</span>
                <span className="text-muted-foreground truncate">
                  {m.pickupDistrict ?? "?"} → {m.dropoffDistrict ?? "?"}
                </span>
                <Badge variant={m.state === "completed" ? "default" : m.state === "failed" || m.state === "cancelled" || m.state === "timeout" ? "destructive" : "secondary"} className="text-[9px]">
                  {m.state}
                </Badge>
              </div>
            ))}
          </TabsContent>

          <TabsContent value="wallet" className="space-y-1.5 mt-3">
            {snap.wallet.length === 0 && <p className="text-xs text-muted-foreground">Aucun mouvement wallet synthétique.</p>}
            {snap.wallet.slice(0, 40).map((w) => (
              <div key={w.id} className="flex items-center justify-between text-[11px] border border-border rounded-md px-2 py-1">
                <span className="text-muted-foreground">{w.kind}</span>
                <span className={`font-mono ${w.amountGnf < 0 ? "text-destructive" : "text-foreground"}`}>
                  {w.amountGnf.toLocaleString("fr-FR")} GNF
                </span>
              </div>
            ))}
          </TabsContent>

          <TabsContent value="events" className="space-y-1 mt-3">
            {snap.events.length === 0 && <p className="text-xs text-muted-foreground">Aucun event.</p>}
            {snap.events.slice(0, 60).map((e) => (
              <div key={e.id} className="flex items-start gap-2 text-[11px]">
                <Activity className={`w-3 h-3 mt-0.5 shrink-0 ${e.level === "error" ? "text-destructive" : e.level === "warn" ? "text-yellow-500" : e.level === "success" ? "text-primary" : "text-muted-foreground"}`} />
                <span className="text-muted-foreground shrink-0 font-mono">{new Date(e.ts).toLocaleTimeString("fr-FR", { hour12: false })}</span>
                <span className="text-foreground break-words">{e.message}</span>
              </div>
            ))}
          </TabsContent>
        </Tabs>

        <Button
          size="sm"
          variant="ghost"
          className="w-full gap-2 mt-4"
          onClick={() => sandboxEngine.clear()}
        >
          <Trash2 className="w-4 h-4" /> Reset sandbox state
        </Button>
      </SheetContent>
    </Sheet>
  );
}