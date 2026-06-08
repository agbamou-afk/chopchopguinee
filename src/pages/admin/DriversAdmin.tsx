import { ModulePage } from "@/components/admin/ModulePage";
import { DataTable, FilterChip, StatGrid, StatusBadge } from "@/components/admin/AdminMock";
import { Button } from "@/components/ui/button";
import { Bike, Activity, Wallet, Check, X, AlertTriangle, FileText, Eye, MessageSquare } from "lucide-react";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { useAdminAuth } from "@/hooks/useAdminAuth";

type Tab = "pending" | "approved" | "suspended" | "needs_info" | "all";

interface DriverRow {
  user_id: string;
  application_id: string | null;
  display_name: string | null;
  phone: string | null;
  email: string | null;
  status: string;
  application_decision: string | null;
  vehicle_type: string;
  plate_number: string | null;
  zones: string[] | null;
  submitted_at: string | null;
  has_selfie: boolean;
  has_id_doc: boolean;
  has_vehicle_photo: boolean;
  missing_required: string[];
  is_complete: boolean;
  rejected_reason: string | null;
  suspended_reason: string | null;
}

const MISSING_LABEL: Record<string, string> = {
  selfie: "Selfie chauffeur",
  id_doc: "Pièce d'identité",
  vehicle_photo: "Photo véhicule",
  plate_number: "Plaque",
  vehicle_type: "Type de véhicule",
  zones: "Zones de service",
};

export default function DriversAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [tab, setTab] = useState<Tab>("pending");
  const [rows, setRows] = useState<DriverRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ approved: 0, pending: 0, needsInfo: 0, cashDue: 0 });
  const [openId, setOpenId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const filter = tab === "all" ? null : tab;
    const { data, error } = await supabase.rpc("admin_list_driver_applications", { p_status: filter } as any);
    if (error) toast.error(error.message);
    setRows((data as DriverRow[]) || []);

    const { data: agg } = await supabase.from("driver_profiles").select("status,cash_debt_gnf");
    if (agg) {
      const pending = agg.filter((r: any) => r.status === "pending").length;
      setStats({
        approved: agg.filter((r: any) => r.status === "approved").length,
        pending,
        needsInfo: (data as DriverRow[] || []).filter((r) => r.application_decision === "more_info").length,
        cashDue: agg.reduce((s: number, r: any) => s + (r.cash_debt_gnf || 0), 0),
      });
    }
    setLoading(false);
  }, [tab]);

  useEffect(() => { load(); }, [load]);

  const decide = async (row: DriverRow, decision: "approve" | "reject" | "suspend" | "reactivate") => {
    if (decision === "approve" && !row.is_complete) {
      if (!isSuperAdmin) {
        toast.error("Impossible d'approuver : documents requis manquants.");
        return;
      }
      const ok = window.confirm("Documents incomplets. Approuver malgré tout (god admin) ?");
      if (!ok) return;
    }
    const reason =
      decision === "reject" || decision === "suspend"
        ? window.prompt(decision === "reject" ? "Motif du refus ?" : "Motif de la suspension ?") || ""
        : "";
    if ((decision === "reject" || decision === "suspend") && !reason.trim()) {
      toast.error("Motif requis");
      return;
    }
    const { error } = await supabase.rpc("driver_admin_decide", {
      p_user_id: row.user_id, p_decision: decision, p_reason: reason || undefined,
    });
    if (error) { toast.error(error.message); return; }
    toast.success("Décision enregistrée");
    setOpenId(null);
    load();
  };

  const fmtDate = (s: string | null) =>
    s ? new Date(s).toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "numeric" }) : "—";

  const detailRow = rows.find((r) => r.user_id === openId) ?? null;

  return (
    <ModulePage module="drivers" title="Chauffeurs" subtitle="Onboarding, opérations et commission cash">
      <StatGrid items={[
        { label: "Approuvés", value: String(stats.approved), icon: Bike, tone: "text-emerald-600" },
        { label: "En attente", value: String(stats.pending), icon: AlertTriangle, tone: "text-amber-500" },
        { label: "Infos demandées", value: String(stats.needsInfo), icon: MessageSquare, tone: "text-primary" },
        { label: "Cash dû", value: formatGNF(stats.cashDue), icon: Wallet, tone: "text-rose-600" },
      ]} />

      <div className="flex gap-2 flex-wrap">
        {(["pending", "needs_info", "approved", "suspended", "all"] as Tab[]).map((t) => (
          <FilterChip
            key={t}
            label={
              t === "pending" ? "En attente" :
              t === "needs_info" ? "Infos demandées" :
              t === "approved" ? "Approuvés" :
              t === "suspended" ? "Suspendus / Refusés" : "Tous"
            }
            active={tab === t}
            onClick={() => setTab(t)}
          />
        ))}
      </div>

      <DataTable
        columns={["Candidat", "Contact", "Véhicule", "Soumis le", "Documents", "Statut", "Actions"]}
        rows={loading ? [] : rows.map((d) => [
          <div className="flex flex-col">
            <span className="font-medium text-sm">{d.display_name || "Candidat sans nom"}</span>
            <span className="font-mono text-[10px] text-muted-foreground">{d.user_id.slice(0, 8)}…</span>
          </div>,
          <div className="flex flex-col text-xs">
            <span>{d.phone || "—"}</span>
            <span className="text-muted-foreground">{d.email || ""}</span>
          </div>,
          <div className="flex flex-col text-xs">
            <span className="capitalize">{d.vehicle_type}</span>
            <span className="text-muted-foreground">{d.plate_number || "Plaque manquante"}</span>
          </div>,
          fmtDate(d.submitted_at),
          d.is_complete
            ? <Badge variant="secondary" className="bg-emerald-100 text-emerald-700">Complet</Badge>
            : <Badge variant="secondary" className="bg-amber-100 text-amber-800">{d.missing_required.length} manquant(s)</Badge>,
          <div className="flex flex-col gap-1">
            <StatusBadge status={d.status} />
            {d.application_decision === "more_info" && (
              <Badge variant="outline" className="text-[10px]">Infos demandées</Badge>
            )}
          </div>,
          <Button size="sm" variant="outline" className="h-8" onClick={() => setOpenId(d.user_id)}>
            <Eye className="w-3.5 h-3.5 mr-1" />Examiner
          </Button>,
        ])}
      />

      <ReviewSheet
        row={detailRow}
        open={!!openId}
        onClose={() => setOpenId(null)}
        onDecide={(decision) => detailRow && decide(detailRow, decision)}
        onReloadNeeded={() => { setOpenId(null); load(); }}
        isSuperAdmin={isSuperAdmin}
      />
    </ModulePage>
  );
}

function ReviewSheet({
  row, open, onClose, onDecide, onReloadNeeded, isSuperAdmin,
}: {
  row: DriverRow | null;
  open: boolean;
  onClose: () => void;
  onDecide: (d: "approve" | "reject" | "suspend" | "reactivate") => void;
  onReloadNeeded: () => void;
  isSuperAdmin: boolean;
}) {
  const [detail, setDetail] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [note, setNote] = useState("");
  const [missing, setMissing] = useState<Record<string, boolean>>({});

  useEffect(() => {
    if (!open || !row) { setDetail(null); return; }
    setLoading(true);
    supabase.rpc("admin_get_driver_application_detail", { p_user_id: row.user_id } as any).then(({ data, error }) => {
      if (error) toast.error(error.message);
      setDetail(data);
      setLoading(false);
    });
    setNote("");
    setMissing({});
  }, [open, row?.user_id]);

  const previewDoc = async (path: string | null | undefined) => {
    if (!path) return;
    const { data, error } = await supabase.functions.invoke("admin-driver-doc-url", { body: { path } });
    if (error || !data?.url) { toast.error("Impossible d'ouvrir le document"); return; }
    window.open(data.url, "_blank", "noopener");
  };

  const requestInfo = async () => {
    if (!row) return;
    if (!note.trim()) { toast.error("Note requise"); return; }
    const items = Object.entries(missing).filter(([, v]) => v).map(([k]) => k);
    if (items.length === 0) { toast.error("Sélectionnez au moins un document manquant"); return; }
    const { error } = await supabase.rpc("admin_request_driver_info", {
      p_user_id: row.user_id, p_missing: items, p_note: note,
    } as any);
    if (error) { toast.error(error.message); return; }
    toast.success("Demande envoyée au chauffeur");
    onReloadNeeded();
  };

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent className="w-full sm:max-w-xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{detail?.display_name || row?.display_name || "Candidat"}</SheetTitle>
          <SheetDescription>
            {row?.phone || "—"} · {row?.email || ""}
          </SheetDescription>
        </SheetHeader>

        {loading || !detail ? (
          <div className="py-8 text-center text-sm text-muted-foreground">Chargement…</div>
        ) : (
          <div className="mt-4 space-y-5">
            <section className="rounded-lg border p-3 space-y-1 text-sm">
              <div className="font-semibold">Véhicule</div>
              <div>Type : <span className="capitalize">{detail.vehicle_type}</span></div>
              <div>Plaque : {detail.plate_number || <span className="text-rose-600">manquante</span>}</div>
              <div>Zones : {(detail.zones || []).length ? (detail.zones as string[]).join(", ") : <span className="text-muted-foreground">aucune</span>}</div>
            </section>

            <section className="rounded-lg border p-3">
              <div className="font-semibold mb-2 flex items-center gap-2"><FileText className="w-4 h-4" />Documents de vérification</div>
              <DocRow label="Selfie chauffeur" present={!!detail.has_selfie} path={detail.driver_photo_path} onPreview={previewDoc} />
              <DocRow label="Pièce d'identité" present={!!detail.has_id_doc} path={detail.id_doc_path} onPreview={previewDoc} />
              <DocRow label="Photo véhicule" present={!!detail.has_vehicle_photo} path={detail.vehicle_photo_path} onPreview={previewDoc} />
            </section>

            <section className="rounded-lg border p-3">
              <div className="font-semibold mb-2">Prêt pour examen</div>
              {row?.is_complete ? (
                <Badge className="bg-emerald-100 text-emerald-700">Documents complets</Badge>
              ) : (
                <div className="text-sm text-amber-700">
                  Manquant : {row?.missing_required.map((k) => MISSING_LABEL[k] || k).join(", ")}
                </div>
              )}
            </section>

            <section className="rounded-lg border p-3 space-y-2">
              <div className="font-semibold">Demander des informations</div>
              <div className="grid grid-cols-2 gap-1 text-sm">
                {Object.entries(MISSING_LABEL).map(([k, l]) => (
                  <label key={k} className="flex items-center gap-2">
                    <Checkbox checked={!!missing[k]} onCheckedChange={(v) => setMissing((m) => ({ ...m, [k]: !!v }))} />
                    {l}
                  </label>
                ))}
              </div>
              <Textarea placeholder="Note pour le chauffeur (obligatoire)" value={note} onChange={(e) => setNote(e.target.value)} />
              <Button size="sm" variant="outline" onClick={requestInfo}>
                <MessageSquare className="w-4 h-4 mr-1" />Envoyer la demande d'infos
              </Button>
            </section>

            <section className="flex flex-wrap gap-2 pt-2 border-t">
              {row?.status === "pending" || row?.status === "rejected" ? (
                <>
                  <Button
                    size="sm"
                    className="gradient-primary"
                    disabled={!row?.is_complete && !isSuperAdmin}
                    title={!row?.is_complete && !isSuperAdmin ? "Documents requis manquants" : undefined}
                    onClick={() => onDecide("approve")}
                  >
                    <Check className="w-4 h-4 mr-1" />Approuver
                  </Button>
                  <Button size="sm" variant="ghost" className="text-destructive" onClick={() => onDecide("reject")}>
                    <X className="w-4 h-4 mr-1" />Refuser
                  </Button>
                </>
              ) : row?.status === "approved" ? (
                <Button size="sm" variant="ghost" className="text-destructive" onClick={() => onDecide("suspend")}>
                  Suspendre
                </Button>
              ) : row?.status === "suspended" ? (
                <Button size="sm" onClick={() => onDecide("reactivate")}>Réactiver</Button>
              ) : null}
            </section>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}

function DocRow({
  label, present, path, onPreview,
}: { label: string; present: boolean; path: string | null; onPreview: (p: string | null) => void }) {
  return (
    <div className="flex items-center justify-between py-1.5 text-sm">
      <span>{label}</span>
      <div className="flex items-center gap-2">
        {present ? (
          <>
            <Badge variant="secondary" className="bg-emerald-100 text-emerald-700">Reçu</Badge>
            <Button size="sm" variant="ghost" className="h-7" onClick={() => onPreview(path)}>
              <Eye className="w-3.5 h-3.5 mr-1" />Aperçu
            </Button>
          </>
        ) : (
          <Badge variant="secondary" className="bg-rose-100 text-rose-700">Manquant</Badge>
        )}
      </div>
    </div>
  );
}
