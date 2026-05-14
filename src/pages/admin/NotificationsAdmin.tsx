import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { MessageSquare, Send, CheckCircle2, XCircle, RefreshCw, AlertTriangle } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

type DiagRow = {
  id: string;
  source: "message_log" | "notification_log";
  template: string;
  channel: string;
  recipient: string | null;
  status: string;
  sent_at: string | null;
  failed_at: string | null;
  retry_count: number;
  provider: string | null;
  provider_response: unknown;
  error: string | null;
  created_at: string;
};

function fmt(ts: string | null) {
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "medium" });
}

function isFailure(s: string) {
  return ["failed", "dlq", "error", "bounced"].includes(s.toLowerCase());
}

function NotificationDiagnostics() {
  const [rows, setRows] = useState<DiagRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState<"all" | "failed" | "sent" | "pending">("all");
  const [channelFilter, setChannelFilter] = useState<string>("all");
  const [search, setSearch] = useState("");

  const load = async () => {
    setLoading(true);
    try {
      const [m, n] = await Promise.all([
        supabase
          .from("message_log")
          .select("id,channel,template,status,provider,provider_message_id,error,retry_count,sent_at,delivered_at,created_at,to_address,payload")
          .order("created_at", { ascending: false })
          .limit(200),
        supabase
          .from("notification_log")
          .select("id,channel,template,status,priority,error_message,recipient,external_id,payload,created_at,updated_at")
          .order("created_at", { ascending: false })
          .limit(200),
      ]);
      const mr: DiagRow[] = (m.data ?? []).map((r: any) => ({
        id: r.id,
        source: "message_log",
        template: String(r.template ?? "—"),
        channel: String(r.channel ?? "—"),
        recipient: r.to_address ?? null,
        status: String(r.status ?? "unknown"),
        sent_at: r.sent_at ?? r.delivered_at ?? null,
        failed_at: isFailure(String(r.status ?? "")) ? r.created_at : null,
        retry_count: Number(r.retry_count ?? 0),
        provider: r.provider ?? null,
        provider_response: r.payload ?? r.provider_message_id ?? null,
        error: r.error ?? null,
        created_at: r.created_at,
      }));
      const nr: DiagRow[] = (n.data ?? []).map((r: any) => ({
        id: r.id,
        source: "notification_log",
        template: String(r.template ?? "—"),
        channel: String(r.channel ?? "—"),
        recipient: r.recipient ?? null,
        status: String(r.status ?? "unknown"),
        sent_at: r.status === "sent" || r.status === "delivered" ? r.updated_at : null,
        failed_at: isFailure(String(r.status ?? "")) ? r.updated_at : null,
        retry_count: 0,
        provider: null,
        provider_response: r.payload ?? r.external_id ?? null,
        error: r.error_message ?? null,
        created_at: r.created_at,
      }));
      const merged = [...mr, ...nr].sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
      setRows(merged);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const channels = useMemo(() => Array.from(new Set(rows.map((r) => r.channel))).sort(), [rows]);

  const filtered = useMemo(() => {
    return rows.filter((r) => {
      if (statusFilter === "failed" && !isFailure(r.status)) return false;
      if (statusFilter === "sent" && !["sent", "delivered", "completed"].includes(r.status.toLowerCase())) return false;
      if (statusFilter === "pending" && !["pending", "queued"].includes(r.status.toLowerCase())) return false;
      if (channelFilter !== "all" && r.channel !== channelFilter) return false;
      if (search && !(r.recipient ?? "").toLowerCase().includes(search.toLowerCase()) && !r.template.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [rows, statusFilter, channelFilter, search]);

  const failedCount = rows.filter((r) => isFailure(r.status)).length;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Rechercher destinataire ou template…"
          className="flex-1 min-w-48 h-9 rounded-md border bg-background px-3 text-sm"
        />
        <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as typeof statusFilter)}>
          <SelectTrigger className="w-36 h-9"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tous statuts</SelectItem>
            <SelectItem value="failed">Échecs</SelectItem>
            <SelectItem value="sent">Envoyés</SelectItem>
            <SelectItem value="pending">En attente</SelectItem>
          </SelectContent>
        </Select>
        <Select value={channelFilter} onValueChange={setChannelFilter}>
          <SelectTrigger className="w-36 h-9"><SelectValue placeholder="Canal" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">Tous canaux</SelectItem>
            {channels.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
          </SelectContent>
        </Select>
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCw className={`w-4 h-4 mr-1 ${loading ? "animate-spin" : ""}`} /> Actualiser
        </Button>
      </div>

      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <AlertTriangle className="w-3.5 h-3.5 text-rose-600" />
        {failedCount} échec(s) parmi les {rows.length} dernières notifications.
      </div>

      <div className="rounded-lg border overflow-hidden">
        <div className="grid grid-cols-[1.2fr_0.8fr_0.8fr_1.2fr_1.2fr_0.6fr_1fr] gap-2 px-3 py-2 text-[11px] uppercase tracking-wide text-muted-foreground bg-muted/40 border-b">
          <div>Type / Template</div>
          <div>Canal</div>
          <div>Statut</div>
          <div>Envoyé</div>
          <div>Échec</div>
          <div>Retry</div>
          <div>Réponse provider</div>
        </div>
        {filtered.length === 0 && (
          <div className="p-6 text-sm text-muted-foreground text-center">Aucune notification correspondante.</div>
        )}
        {filtered.slice(0, 100).map((r) => (
          <div
            key={`${r.source}-${r.id}`}
            className={`grid grid-cols-[1.2fr_0.8fr_0.8fr_1.2fr_1.2fr_0.6fr_1fr] gap-2 px-3 py-2 text-xs border-b last:border-b-0 ${isFailure(r.status) ? "bg-rose-50/50 dark:bg-rose-950/20" : ""}`}
          >
            <div className="min-w-0">
              <p className="font-medium truncate">{r.template}</p>
              <p className="text-[10px] text-muted-foreground truncate">{r.recipient ?? "—"} · {r.source}</p>
            </div>
            <div className="self-center">{r.channel}</div>
            <div className="self-center"><StatusBadge status={r.status} /></div>
            <div className="self-center text-muted-foreground">{fmt(r.sent_at)}</div>
            <div className="self-center text-muted-foreground">{fmt(r.failed_at)}</div>
            <div className="self-center tabular-nums">{r.retry_count}</div>
            <div className="min-w-0 self-center">
              {r.error ? (
                <span className="text-rose-600 truncate block" title={r.error}>{r.error}</span>
              ) : (
                <code className="text-[10px] text-muted-foreground truncate block" title={JSON.stringify(r.provider_response)}>
                  {r.provider_response ? JSON.stringify(r.provider_response).slice(0, 80) : "—"}
                </code>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

const TEMPLATES = [
  { name: "OTP", channel: "whatsapp", body: "Votre code CHOP CHOP : {{code}}", status: "active" },
  { name: "Wallet top-up success", channel: "whatsapp", body: "Recharge confirmée : {{amount}} GNF", status: "active" },
  { name: "Ride confirmed", channel: "sms", body: "Course confirmée. Chauffeur arrive dans {{eta}}.", status: "active" },
  { name: "Refund issued", channel: "whatsapp", body: "Remboursement de {{amount}} GNF effectué.", status: "active" },
];

const RECENT = [
  { to: "+224 622...", template: "OTP", status: "completed", t: "il y a 1 min" },
  { to: "+224 620...", template: "Ride confirmed", status: "completed", t: "il y a 3 min" },
  { to: "+224 628...", template: "Wallet success", status: "failed", t: "il y a 12 min" },
];

export default function NotificationsAdmin() {
  return (
    <ModulePage module="notifications" title="Notifications" subtitle="WhatsApp, SMS, push et campagnes">
      <StatGrid items={[
        { label: "Envoyés 24h", value: "12 480", icon: Send, tone: "text-primary" },
        { label: "Délivrés", value: "98.2%", icon: CheckCircle2, tone: "text-emerald-600" },
        { label: "Échecs", value: "224", icon: XCircle, tone: "text-rose-600" },
        { label: "Templates actifs", value: "18", icon: MessageSquare, tone: "text-amber-600" },
      ]} />
      <Tabs defaultValue="templates">
        <TabsList>
          <TabsTrigger value="templates">Templates</TabsTrigger>
          <TabsTrigger value="broadcast">Diffusion</TabsTrigger>
          <TabsTrigger value="log">Journal</TabsTrigger>
          <TabsTrigger value="diagnostics">Diagnostics</TabsTrigger>
        </TabsList>
        <TabsContent value="templates" className="mt-4 space-y-2">
          {TEMPLATES.map((t) => (
            <Card key={t.name} className="p-4 flex items-center gap-3">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="font-semibold text-sm">{t.name}</p>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-muted">{t.channel}</span>
                  <StatusBadge status={t.status} />
                </div>
                <p className="text-xs text-muted-foreground truncate mt-0.5">{t.body}</p>
              </div>
              <Button size="sm" variant="ghost">Éditer</Button>
            </Card>
          ))}
        </TabsContent>
        <TabsContent value="broadcast" className="mt-4">
          <Card className="p-5 space-y-3">
            <p className="text-sm font-semibold">Composer une annonce</p>
            <Textarea rows={4} placeholder="Message à diffuser à tous les utilisateurs actifs..." />
            <div className="flex gap-2">
              <Button className="gradient-primary"><Send className="w-4 h-4 mr-1" /> Diffuser</Button>
              <Button variant="outline">Programmer</Button>
            </div>
            <p className="text-xs text-muted-foreground">⚠ Action sensible — approbation Super Admin requise.</p>
          </Card>
        </TabsContent>
        <TabsContent value="log" className="mt-4 space-y-2">
          <AdminToolbar placeholder="Rechercher destinataire..." />
          {RECENT.map((r, i) => (
            <Card key={i} className="p-3 flex items-center gap-3">
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium">{r.to}</p>
                <p className="text-xs text-muted-foreground">{r.template} · {r.t}</p>
              </div>
              <StatusBadge status={r.status} />
            </Card>
          ))}
        </TabsContent>
        <TabsContent value="diagnostics" className="mt-4">
          <NotificationDiagnostics />
        </TabsContent>
      </Tabs>
    </ModulePage>
  );
}
