import { useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import type { DriverGroup } from "@/lib/admin/driverGroups";
import {
  adminGroupScorecard, adminGroupRiskScorecard, adminIncentiveSuggestions,
  listMilestoneJobRuns, signedCheckinPhotoUrl,
  type GroupScorecard, type GroupRiskRow, type IncentiveSuggestion, type MilestoneJobRun,
} from "@/lib/admin/driverGroupsV5";
import { formatGnf } from "@/lib/admin/driverGroups";
import { adminListCheckins, type FieldCheckin } from "@/lib/admin/driverGroupsV4";

export function ScorecardsPanel({ groups }: { groups: DriverGroup[] }) {
  const [selected, setSelected] = useState<string>(groups[0]?.id ?? "");
  const [days, setDays] = useState(30);
  const [card, setCard] = useState<GroupScorecard | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => { if (!selected && groups[0]) setSelected(groups[0].id); }, [groups, selected]);
  useEffect(() => {
    if (!selected) return;
    setLoading(true);
    adminGroupScorecard(selected, days)
      .then(setCard)
      .catch((e) => toast({ title: "Erreur", description: e?.message, variant: "destructive" }))
      .finally(() => setLoading(false));
  }, [selected, days]);

  return (
    <div className="space-y-3">
      <Card className="p-3 flex flex-wrap items-center gap-2">
        <select className="h-9 px-2 text-sm bg-background border border-border rounded"
          value={selected} onChange={e => setSelected(e.target.value)}>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        {[7, 30, 90].map(d => (
          <button key={d} onClick={() => setDays(d)}
            className={`text-[11px] px-2 py-1 rounded border ${days === d ? "bg-primary text-primary-foreground border-primary" : "bg-background border-border text-muted-foreground"}`}>{d}j</button>
        ))}
      </Card>
      {loading || !card ? (
        <Card className="p-6 text-center text-sm text-muted-foreground">Chargement…</Card>
      ) : (
        <Card className="p-4 grid grid-cols-2 md:grid-cols-3 gap-2 text-sm">
          <Metric label="Recrutés" value={card.recruited} />
          <Metric label="Approuvés" value={card.approved} />
          <Metric label="Chauffeurs actifs" value={card.active_drivers} />
          <Metric label="Courses complétées" value={card.rides_completed ?? 0} />
          <Metric label="Revenu chauffeur brut" value={formatGnf(card.gross_earnings_gnf ?? 0)} />
          <Metric label="Commissions en attente" value={formatGnf(card.commissions_pending_gnf)} />
          <Metric label="Commissions payées" value={formatGnf(card.commissions_paid_gnf)} />
          <Metric label="Bonus éligibles" value={card.signup_bonuses_eligible} />
          <Metric label="Bonus payés" value={formatGnf(card.signup_bonuses_paid_gnf ?? 0)} />
          <Metric label="Check-ins" value={card.checkins_count} />
          <Metric label="Items en revue risque" value={card.risk_held_count ?? 0} />
        </Card>
      )}
      <p className="text-[10px] text-muted-foreground">
        Métriques calculées à partir des courses, parrainages et commissions réels. "0" indique zéro effectif sur la période.
      </p>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="border border-border/40 rounded p-2">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="font-semibold tabular-nums">{value}</p>
    </div>
  );
}

export function SuggestionsPanel() {
  const [rows, setRows] = useState<IncentiveSuggestion[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    adminIncentiveSuggestions()
      .then(setRows)
      .catch((e) => toast({ title: "Erreur", description: e?.message, variant: "destructive" }))
      .finally(() => setLoading(false));
  }, []);
  return (
    <Card className="p-4 space-y-2">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Suggestions opérationnelles</h3>
        <span className="text-[10px] text-muted-foreground">Non-automatique · revue manuelle requise</span>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucune suggestion fiable pour le moment.</p>
        : rows.map((s, i) => (
          <div key={i} className="border border-border/40 rounded p-2 space-y-1">
            <div className="flex items-center justify-between">
              <span className="text-[10px] uppercase tracking-wider text-muted-foreground">{s.kind}</span>
              <span className={`text-[10px] px-1.5 py-0.5 rounded ${s.severity === "high" ? "bg-destructive/15 text-destructive" : s.severity === "medium" ? "bg-amber-500/15 text-amber-700" : "bg-muted"}`}>{s.severity}</span>
            </div>
            <p className="text-sm">{s.message}</p>
          </div>
        ))}
      <p className="text-[10px] text-muted-foreground pt-2 border-t border-border/40">
        Les suggestions ne modifient ni les commissions ni les paiements. Toute action reste manuelle.
      </p>
    </Card>
  );
}

export function RiskScorecardPanel() {
  const [rows, setRows] = useState<GroupRiskRow[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    adminGroupRiskScorecard()
      .then(setRows)
      .catch((e) => toast({ title: "Erreur", description: e?.message, variant: "destructive" }))
      .finally(() => setLoading(false));
  }, []);
  return (
    <Card className="p-4 space-y-2">
      <h3 className="text-sm font-semibold">Scorecard risque par groupe</h3>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucun groupe.</p>
        : (
          <table className="w-full text-[12px]">
            <thead><tr className="text-left text-muted-foreground"><th>Groupe</th><th>Réf.</th><th>Held</th><th>Review</th><th>Comm. held</th><th>Dernière revue</th></tr></thead>
            <tbody>{rows.map(r => (
              <tr key={r.group_id} className="border-t border-border/40">
                <td>{r.group_name}</td>
                <td className="tabular-nums">{r.referrals_count}</td>
                <td className="tabular-nums">{r.risk_held}</td>
                <td className="tabular-nums">{r.risk_review}</td>
                <td className="tabular-nums">{r.commissions_held}</td>
                <td className="text-[10px] text-muted-foreground">{r.last_review_at ? new Date(r.last_review_at).toLocaleDateString("fr-FR") : "—"}</td>
              </tr>
            ))}</tbody>
          </table>
        )}
      <p className="text-[10px] text-muted-foreground pt-2 border-t border-border/40">
        Lecture seule. Aucune action automatique de suspension ou de pénalité.
      </p>
    </Card>
  );
}

export function SchedulerStatusPanel() {
  const [runs, setRuns] = useState<MilestoneJobRun[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    listMilestoneJobRuns()
      .then(setRuns)
      .catch((e) => toast({ title: "Erreur", description: e?.message, variant: "destructive" }))
      .finally(() => setLoading(false));
  }, []);
  const last = runs[0];
  return (
    <Card className="p-4 space-y-2">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold">Planification jalons</h3>
        <span className="text-[10px] px-1.5 py-0.5 rounded bg-primary/15 text-primary">cron actif · toutes les 10 min</span>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : !last ? <p className="text-sm text-muted-foreground">Aucun run enregistré pour l'instant. Le job s'exécute toutes les 10 min.</p>
        : (
          <div className="text-[12px] space-y-1">
            <p>Dernier run : <span className="font-mono">{new Date(last.ran_at).toLocaleString("fr-FR")}</span> · traités {last.processed} · éligibles {last.eligible} · échecs {last.failed}{last.error ? ` · erreur ${last.error}` : ""}</p>
            <p className="text-muted-foreground">Historique récent :</p>
            <ul className="space-y-0.5 max-h-40 overflow-auto">
              {runs.map(r => (
                <li key={r.id} className="text-[11px] tabular-nums">
                  {new Date(r.ran_at).toLocaleString("fr-FR")} — p{r.processed}/e{r.eligible}/f{r.failed}{r.error ? ` ⚠ ${r.error}` : ""}
                </li>
              ))}
            </ul>
          </div>
        )}
    </Card>
  );
}

export function CheckinPhotoThumb({ path }: { path: string }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => { signedCheckinPhotoUrl(path, 600).then(setUrl); }, [path]);
  if (!url) return <span className="text-[10px] text-muted-foreground">photo…</span>;
  return (
    <a href={url} target="_blank" rel="noreferrer">
      <img src={url} alt="check-in" loading="lazy" className="w-16 h-16 object-cover rounded border border-border/40" />
    </a>
  );
}

export function CheckinsWithPhotos({ groups }: { groups: DriverGroup[] }) {
  const [rows, setRows] = useState<FieldCheckin[]>([]);
  const [loading, setLoading] = useState(true);
  const [groupId, setGroupId] = useState("");
  useEffect(() => {
    setLoading(true);
    adminListCheckins(groupId || null)
      .then(setRows)
      .catch((e) => toast({ title: "Erreur", description: e?.message, variant: "destructive" }))
      .finally(() => setLoading(false));
  }, [groupId]);
  const groupName = (id: string) => groups.find(g => g.id === id)?.name ?? id.slice(0, 8);
  return (
    <Card className="p-4 space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-semibold">Check-ins terrain (avec photos)</h3>
        <select className="bg-background border border-border rounded text-xs h-8 px-2"
          value={groupId} onChange={e => setGroupId(e.target.value)}>
          <option value="">Tous les groupes</option>
          {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
      </div>
      {loading ? <p className="text-sm text-muted-foreground">Chargement…</p>
        : rows.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Aucun check-in.</p>
        : rows.map(c => (
          <div key={c.id} className="border border-border/40 rounded p-2 text-sm flex gap-3">
            {c.photo_url && <CheckinPhotoThumb path={c.photo_url} />}
            <div className="flex-1 space-y-1">
              <div className="flex justify-between">
                <p className="font-medium text-[12px]">{groupName(c.group_id)} · {c.checkin_type}</p>
                <span className="text-[10px] text-muted-foreground">{new Date(c.created_at).toLocaleString("fr-FR")}</span>
              </div>
              {c.notes && <p className="text-[11px] text-muted-foreground">{c.notes}</p>}
              {(c.lat && c.lng) && (
                <p className="text-[10px] text-muted-foreground tabular-nums">{c.lat.toFixed(5)}, {c.lng.toFixed(5)}</p>
              )}
            </div>
          </div>
        ))}
    </Card>
  );
}