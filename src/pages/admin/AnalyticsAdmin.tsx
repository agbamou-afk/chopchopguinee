import { useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Loader2, Sparkles, RefreshCw, TrendingUp, Search, AlertTriangle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import {
  ResponsiveContainer, LineChart, Line, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid,
} from "recharts";

interface Summary {
  window_days: number;
  total_events: number;
  active_users: number;
  active_sessions: number;
  by_day: { day: string; n: number }[];
  by_category: { category: string; n: number }[];
  top_events: { name: string; n: number }[];
  top_routes: { route: string; n: number }[];
  top_zones: { zone: string; n: number }[];
  top_search: { q: string; n: number }[];
  failed_search: { q: string; n: number }[];
}

interface Insight {
  id: string;
  section: string;
  title: string;
  summary: string;
  recommendation: string | null;
  confidence: "low" | "medium" | "high";
  status: string;
  created_at: string;
}

const SECTION_LABEL: Record<string, string> = {
  executive: "Résumé exécutif", behavior: "Comportement", mobility: "Mobilité",
  wallet: "CHOPWallet", marketplace: "Marché", driver: "Chauffeurs",
  merchant: "Marchands", fraud: "Fraude", growth: "Croissance", recommendation: "Recommandation",
};

export default function AnalyticsAdmin() {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [insights, setInsights] = useState<Insight[]>([]);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);

  async function load() {
    setLoading(true);
    const [{ data: s }, { data: ins }] = await Promise.all([
      supabase.rpc("analytics_summary", { p_days: 7 }),
      supabase
        .from("ai_insights")
        .select("id, section, title, summary, recommendation, confidence, status, created_at")
        .order("created_at", { ascending: false })
        .limit(20),
    ]);
    setSummary(s as unknown as Summary);
    setInsights((ins ?? []) as Insight[]);
    setLoading(false);
  }

  useEffect(() => {
    void load();
  }, []);

  async function generate() {
    setGenerating(true);
    const { data, error } = await supabase.functions.invoke("generate-ai-insights", {
      body: { days: 7 },
    });
    setGenerating(false);
    if (error || (data as any)?.error) {
      toast({
        title: "Génération impossible",
        description: (data as any)?.error || error?.message || "Erreur inconnue",
        variant: "destructive",
      });
      return;
    }
    toast({ title: `${(data as any)?.inserted ?? 0} insight(s) générés` });
    void load();
  }

  async function setStatus(id: string, status: "accepted" | "rejected") {
    await supabase.from("ai_insights").update({ status, reviewed_at: new Date().toISOString() }).eq("id", id);
    void load();
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground">
        <Loader2 className="w-5 h-5 animate-spin mr-2" /> Chargement…
      </div>
    );
  }

  const empty = !summary || summary.total_events === 0;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-xl font-semibold">Analytique & Intelligence IA</h1>
          <p className="text-sm text-muted-foreground">7 derniers jours · données privacy-first</p>
        </div>
        <div className="flex gap-2">
          <Button size="sm" variant="outline" onClick={load}>
            <RefreshCw className="w-4 h-4 mr-1" /> Actualiser
          </Button>
          <Button size="sm" onClick={generate} disabled={generating}>
            {generating ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : <Sparkles className="w-4 h-4 mr-1" />}
            Générer insights IA
          </Button>
        </div>
      </div>

      {empty ? (
        <Card className="p-8 text-center text-muted-foreground rounded-2xl">
          Aucun événement collecté sur cette fenêtre. Les graphiques apparaîtront dès la première activité.
        </Card>
      ) : (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <KpiCard label="Événements" value={summary!.total_events} />
            <KpiCard label="Utilisateurs actifs" value={summary!.active_users} />
            <KpiCard label="Sessions" value={summary!.active_sessions} />
            <KpiCard label="Catégories" value={summary!.by_category.length} />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <ChartCard icon={TrendingUp} title="Activité par jour">
              <ResponsiveContainer width="100%" height={220}>
                <LineChart data={summary!.by_day.map((d) => ({ day: d.day.slice(5, 10), n: d.n }))}>
                  <CartesianGrid strokeDasharray="3 3" opacity={0.2} />
                  <XAxis dataKey="day" fontSize={11} />
                  <YAxis fontSize={11} />
                  <Tooltip />
                  <Line type="monotone" dataKey="n" stroke="hsl(var(--primary))" strokeWidth={2} dot={false} />
                </LineChart>
              </ResponsiveContainer>
            </ChartCard>

            <ChartCard icon={TrendingUp} title="Top catégories">
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={summary!.by_category}>
                  <CartesianGrid strokeDasharray="3 3" opacity={0.2} />
                  <XAxis dataKey="category" fontSize={11} />
                  <YAxis fontSize={11} />
                  <Tooltip />
                  <Bar dataKey="n" fill="hsl(var(--primary))" radius={[6, 6, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </ChartCard>

            <ChartCard icon={Search} title="Top recherches">
              <ListBars items={summary!.top_search.map((x) => ({ label: x.q, n: x.n }))} empty="Pas encore de recherche." />
            </ChartCard>

            <ChartCard icon={AlertTriangle} title="Recherches sans résultat">
              <ListBars items={summary!.failed_search.map((x) => ({ label: x.q, n: x.n }))} empty="Aucune recherche infructueuse." tone="warn" />
            </ChartCard>

            <ChartCard icon={TrendingUp} title="Top événements">
              <ListBars items={summary!.top_events.map((x) => ({ label: x.name, n: x.n }))} empty="—" />
            </ChartCard>

            <ChartCard icon={TrendingUp} title="Top zones (consenties)">
              <ListBars items={summary!.top_zones.map((x) => ({ label: x.zone, n: x.n }))} empty="Aucune donnée de zone." />
            </ChartCard>
          </div>
        </>
      )}

      <section>
        <h2 className="text-base font-semibold mb-2 flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-primary" /> Insights IA récents
        </h2>
        {insights.length === 0 ? (
          <Card className="p-6 text-center text-sm text-muted-foreground rounded-2xl">
            Aucun insight généré. Cliquez « Générer insights IA » pour démarrer.
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {insights.map((i) => (
              <Card key={i.id} className="p-4 rounded-2xl space-y-2">
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge variant="secondary">{SECTION_LABEL[i.section] ?? i.section}</Badge>
                  <Badge variant={i.confidence === "high" ? "default" : "outline"}>
                    Confiance : {i.confidence}
                  </Badge>
                  {i.status !== "new" && <Badge variant="outline">{i.status}</Badge>}
                </div>
                <h3 className="text-sm font-semibold">{i.title}</h3>
                <p className="text-sm text-muted-foreground leading-relaxed">{i.summary}</p>
                {i.recommendation && (
                  <p className="text-xs bg-primary/5 border border-primary/20 rounded-lg p-2 text-foreground">
                    <span className="font-semibold">Action humaine suggérée — </span>{i.recommendation}
                  </p>
                )}
                {i.status === "new" && (
                  <div className="flex gap-2 pt-1">
                    <Button size="sm" variant="outline" onClick={() => setStatus(i.id, "accepted")}>Accepter</Button>
                    <Button size="sm" variant="ghost" onClick={() => setStatus(i.id, "rejected")}>Rejeter</Button>
                  </div>
                )}
              </Card>
            ))}
          </div>
        )}
      </section>

      <p className="text-[11px] text-muted-foreground/80 text-center">
        L'IA recommande uniquement. Aucune action automatique : ni remboursement, ni gel, ni envoi de message.
      </p>
    </div>
  );
}

function KpiCard({ label, value }: { label: string; value: number }) {
  return (
    <Card className="p-4 rounded-2xl">
      <p className="text-[11px] uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="text-2xl font-semibold">{value.toLocaleString("fr-FR")}</p>
    </Card>
  );
}

function ChartCard({ icon: Icon, title, children }: { icon: React.ComponentType<{ className?: string }>; title: string; children: React.ReactNode }) {
  return (
    <Card className="p-4 rounded-2xl">
      <h3 className="text-sm font-semibold flex items-center gap-2 mb-3">
        <Icon className="w-4 h-4 text-primary" /> {title}
      </h3>
      {children}
    </Card>
  );
}

function ListBars({ items, empty, tone }: { items: { label: string; n: number }[]; empty: string; tone?: "warn" }) {
  if (items.length === 0) return <p className="text-xs text-muted-foreground py-6 text-center">{empty}</p>;
  const max = Math.max(...items.map((i) => i.n));
  return (
    <div className="space-y-1.5">
      {items.map((it) => (
        <div key={it.label} className="text-xs">
          <div className="flex justify-between">
            <span className="truncate pr-2">{it.label}</span>
            <span className="text-muted-foreground tabular-nums">{it.n}</span>
          </div>
          <div className="h-1.5 bg-muted rounded-full overflow-hidden">
            <div
              className={tone === "warn" ? "h-full bg-[hsl(8_78%_55%)]" : "h-full bg-primary"}
              style={{ width: `${(it.n / max) * 100}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}