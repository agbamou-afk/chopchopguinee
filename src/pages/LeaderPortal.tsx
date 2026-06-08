import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/AuthContext";
import { Seo } from "@/components/Seo";
import {
  leaderGetMyGroup, leaderListMyMembers, leaderListMyCommissions,
  leaderListMyReferrals, leaderGetMyStats, type LeaderMember,
  leaderListMyCampaigns, leaderListMyContracts, leaderListMyStatements,
  leaderListMyCheckins, leaderCreateCheckin,
} from "@/lib/leader/driverGroup";
import { formatGnf, type DriverGroup, type DriverGroupCommission, type DriverReferral, type DriverGroupStats } from "@/lib/admin/driverGroups";
import type { RecruitmentCampaign, GroupContract, PayoutStatement } from "@/lib/admin/driverGroupsV3";
import type { FieldCheckin } from "@/lib/admin/driverGroupsV4";
import { uploadCheckinPhoto, leaderMyScorecard, signedCheckinPhotoUrl, downloadStatementCsvRich, type GroupScorecard } from "@/lib/admin/driverGroupsV5";
import { leaderListMyStatementItems } from "@/lib/leader/driverGroup";
import { Users2, Coins, Gift, Map as MapIcon, ArrowLeft } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";

type Tab = "overview" | "drivers" | "commissions" | "referrals" | "campaigns" | "contracts" | "statements" | "checkins";

export default function LeaderPortal() {
  const { user, ready: authReady } = useAuth();
  const authLoading = !authReady;
  const navigate = useNavigate();
  const [tab, setTab] = useState<Tab>("overview");
  const [group, setGroup] = useState<DriverGroup | null>(null);
  const [members, setMembers] = useState<LeaderMember[]>([]);
  const [commissions, setCommissions] = useState<DriverGroupCommission[]>([]);
  const [referrals, setReferrals] = useState<DriverReferral[]>([]);
  const [stats, setStats] = useState<DriverGroupStats | null>(null);
  const [campaigns, setCampaigns] = useState<RecruitmentCampaign[]>([]);
  const [contracts, setContracts] = useState<GroupContract[]>([]);
  const [statements, setStatements] = useState<PayoutStatement[]>([]);
  const [checkins, setCheckins] = useState<FieldCheckin[]>([]);
  const [checkinOpen, setCheckinOpen] = useState(false);
  const [scorecard, setScorecard] = useState<GroupScorecard | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { navigate("/auth"); return; }
    let cancel = false;
    (async () => {
      try {
        const g = await leaderGetMyGroup();
        if (cancel) return;
        if (!g) { setGroup(null); setLoading(false); return; }
        setGroup(g);
        const [m, c, r, s, ca, co, st, ck, sc] = await Promise.all([
          leaderListMyMembers(), leaderListMyCommissions(), leaderListMyReferrals(), leaderGetMyStats(30),
          leaderListMyCampaigns(), leaderListMyContracts(), leaderListMyStatements(),
          leaderListMyCheckins(50),
          leaderMyScorecard(30),
        ]);
        if (cancel) return;
        setMembers(m); setCommissions(c); setReferrals(r); setStats(s);
        setCampaigns(ca); setContracts(co); setStatements(st);
        setCheckins(ck);
        setScorecard(sc);
      } catch (e: any) {
        if (!cancel) setErr(e?.message ?? String(e));
      } finally {
        if (!cancel) setLoading(false);
      }
    })();
    return () => { cancel = true; };
  }, [user, authLoading, navigate]);

  if (authLoading || loading) {
    return <div className="p-6 text-sm text-muted-foreground">Chargement…</div>;
  }

  if (err) {
    return (
      <div className="max-w-md mx-auto p-6 space-y-3">
        <Card className="p-4 text-sm">Erreur : {err}</Card>
      </div>
    );
  }

  if (!group) {
    return (
      <div className="max-w-md mx-auto p-6 space-y-3">
        <Seo title="Portail leader · CHOP CHOP" description="Accès leader de groupe chauffeurs" />
        <Card className="p-6 text-center space-y-3">
          <Users2 className="w-8 h-8 mx-auto text-muted-foreground" />
          <p className="font-semibold">Aucun groupe associé</p>
          <p className="text-sm text-muted-foreground">
            Votre compte n'est pas enregistré comme leader d'un groupe chauffeurs. Contactez l'équipe CHOP CHOP pour être ajouté.
          </p>
          <Button variant="outline" onClick={() => navigate("/")}>Retour</Button>
        </Card>
      </div>
    );
  }

  const isSuspended = group.status !== "active";

  return (
    <div className="max-w-3xl mx-auto p-4 space-y-4">
      <Seo title={`${group.name} · Portail leader`} description="Tableau de bord leader CHOP CHOP" />
      <div className="flex items-center justify-between">
        <Button variant="ghost" size="sm" onClick={() => navigate("/")}>
          <ArrowLeft className="w-4 h-4 mr-1" /> Retour
        </Button>
        <span className="text-[11px] uppercase tracking-wider text-muted-foreground">Portail leader</span>
      </div>

      <Card className="p-4 space-y-2">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold">{group.name}</h1>
            <p className="text-xs text-muted-foreground">{group.leader_name || "—"} · {group.leader_phone || "—"}</p>
          </div>
          <span className={`text-[10px] px-2 py-1 rounded ${isSuspended ? "bg-destructive/15 text-destructive" : "bg-primary/15 text-primary"}`}>
            {group.status}
          </span>
        </div>
        {group.assigned_zones?.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {group.assigned_zones.map(z => (
              <span key={z} className="text-[10px] px-1.5 py-0.5 rounded bg-muted flex items-center gap-1">
                <MapIcon className="w-3 h-3" /> {z}
              </span>
            ))}
          </div>
        )}
      </Card>

      {group.referral_code && (
        <Card className="p-4 space-y-2 bg-primary/5 border-primary/30">
          <p className="text-[11px] uppercase tracking-wider text-muted-foreground">Votre code de parrainage</p>
          <div className="flex items-center justify-between gap-3">
            <p className="font-mono text-lg font-semibold">{group.referral_code}</p>
            <Button
              size="sm"
              variant="outline"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(group.referral_code!);
                  toast({ title: "Code copié" });
                } catch {
                  toast({ title: "Impossible de copier", variant: "destructive" });
                }
              }}
            >Copier</Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Partagez ce code avec les chauffeurs que vous recrutez. L'équipe CHOPCHOP vérifie chaque inscription avant validation.
          </p>
        </Card>
      )}

      {isSuspended && (
        <Card className="p-3 text-sm bg-destructive/10 text-destructive border-destructive/30">
          Ce groupe est suspendu. Aucune nouvelle commission ne sera calculée jusqu'à réactivation par CHOP CHOP.
        </Card>
      )}

      {(commissions.some(c => (c as any).risk_status && (c as any).risk_status !== "clear")
        || referrals.some(r => (r as any).risk_status && (r as any).risk_status !== "clear")) && (
        <Card className="p-3 text-sm bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30">
          Certains paiements peuvent être temporairement en vérification par l'équipe CHOPCHOP.
        </Card>
      )}

      <Sheet open={checkinOpen} onOpenChange={setCheckinOpen}>
        <SheetTrigger asChild>
          <Button size="sm" variant="outline" className="w-full">
            <MapIcon className="w-4 h-4 mr-1" /> Nouveau check-in terrain
          </Button>
        </SheetTrigger>
        <SheetContent className="w-full sm:max-w-md">
          <SheetHeader><SheetTitle>Check-in terrain</SheetTitle></SheetHeader>
          <CheckinForm groupId={group.id} onSaved={async () => {
            setCheckinOpen(false);
            try { setCheckins(await leaderListMyCheckins(50)); } catch {}
          }} />
        </SheetContent>
      </Sheet>

      <div className="flex flex-wrap gap-2">
        {([
          ["overview", "Vue d'ensemble"],
          ["drivers", `Chauffeurs (${members.filter(m => m.status === "active").length})`],
          ["commissions", `Commissions (${commissions.length})`],
          ["referrals", `Parrainages (${referrals.length})`],
          ["campaigns", `Campagnes (${campaigns.length})`],
          ["contracts", `Contrats (${contracts.length})`],
          ["statements", `Relevés (${statements.length})`],
          ["checkins", `Check-ins (${checkins.length})`],
        ] as [Tab, string][]).map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
            className={`px-3 py-1.5 text-xs rounded-full border ${tab === k ? "bg-primary text-primary-foreground border-primary" : "bg-background border-border text-muted-foreground"}`}>
            {l}
          </button>
        ))}
      </div>

      {tab === "overview" && (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            <Stat label="Chauffeurs actifs" value={String(stats?.active_drivers ?? 0)} icon={Users2} />
            <Stat label="Courses 30j" value={String(stats?.rides_completed ?? 0)} icon={Coins} />
            <Stat label="Commissions en attente" value={formatGnf(stats?.commissions_pending_gnf ?? 0)} icon={Coins} />
            <Stat label="Commissions payées 30j" value={formatGnf(stats?.commissions_paid_gnf ?? 0)} icon={Coins} />
            <Stat label="Parrainages éligibles" value={String(stats?.signup_bonus_eligible_count ?? 0)} icon={Gift} />
            <Stat label="Bonus payés 30j" value={formatGnf(stats?.signup_bonus_paid_gnf ?? 0)} icon={Gift} />
          </div>
          {scorecard && (
            <Card className="p-3 space-y-2">
              <p className="text-[11px] uppercase tracking-wider text-muted-foreground">Scorecard (30 jours)</p>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div><span className="text-muted-foreground text-[11px]">Recrutés</span><p className="font-semibold tabular-nums">{scorecard.recruited}</p></div>
                <div><span className="text-muted-foreground text-[11px]">Approuvés</span><p className="font-semibold tabular-nums">{scorecard.approved}</p></div>
                <div><span className="text-muted-foreground text-[11px]">Check-ins</span><p className="font-semibold tabular-nums">{scorecard.checkins_count}</p></div>
                <div><span className="text-muted-foreground text-[11px]">Bonus éligibles</span><p className="font-semibold tabular-nums">{scorecard.signup_bonuses_eligible}</p></div>
              </div>
              <p className="text-[10px] text-muted-foreground">Prochaine action conseillée : {scorecard.active_drivers < 3 ? "recruter de nouveaux chauffeurs." : scorecard.checkins_count === 0 ? "effectuer un check-in terrain." : "suivre les chauffeurs inactifs."}</p>
            </Card>
          )}
        </div>
      )}

      {tab === "drivers" && (
        <Card className="p-3 space-y-2">
          {members.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucun chauffeur assigné.</p>
          ) : members.map(m => (
            <div key={m.id} className="flex items-center justify-between text-sm border-b last:border-b-0 border-border/40 pb-2 last:pb-0">
              <div>
                <p className="font-medium">{m.driver_display}</p>
                <p className="text-[11px] text-muted-foreground">
                  {m.assigned_zone || "—"}{m.driver_phone_last4 ? ` · ····${m.driver_phone_last4}` : ""}
                </p>
              </div>
              <span className={`text-[10px] px-1.5 py-0.5 rounded ${m.status === "active" ? "bg-primary/15 text-primary" : "bg-muted"}`}>
                {m.status}
              </span>
            </div>
          ))}
        </Card>
      )}

      {tab === "commissions" && (
        <Card className="p-3 space-y-2">
          {commissions.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucune commission.</p>
          ) : commissions.map(c => (
            <div key={c.id} className="flex items-center justify-between text-sm border-b last:border-b-0 border-border/40 pb-2 last:pb-0">
              <div>
                <p className="font-medium tabular-nums">{formatGnf(c.commission_amount_gnf)}</p>
                <p className="text-[11px] text-muted-foreground">
                  {new Date(c.created_at).toLocaleDateString("fr-FR")} · {c.source_type} · {Number(c.commission_percent).toFixed(2)}%
                </p>
              </div>
              <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{c.status}</span>
            </div>
          ))}
          <p className="text-[10px] text-muted-foreground pt-2 border-t border-border/40">
            Lecture seule. Pour toute modification, contactez l'admin CHOP CHOP.
          </p>
        </Card>
      )}

      {tab === "referrals" && (
        <Card className="p-3 space-y-2">
          {referrals.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucun parrainage.</p>
          ) : referrals.map(r => (
            <div key={r.id} className="flex items-center justify-between text-sm border-b last:border-b-0 border-border/40 pb-2 last:pb-0">
              <div>
                <p className="font-medium font-mono text-[12px]">{r.referred_driver_user_id.slice(0, 8)}…</p>
                <p className="text-[11px] text-muted-foreground">
                  {new Date(r.created_at).toLocaleDateString("fr-FR")} · {formatGnf(r.bonus_amount_gnf)}
                </p>
              </div>
              <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{r.status}</span>
            </div>
          ))}
        </Card>
      )}

      {tab === "campaigns" && (
        <Card className="p-3 space-y-2">
          {campaigns.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucune campagne pour votre groupe.</p>
          ) : campaigns.map(c => (
            <div key={c.id} className="border-b last:border-b-0 border-border/40 pb-2 last:pb-0 text-sm space-y-1">
              <div className="flex justify-between"><p className="font-medium">{c.name}</p><span className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{c.status}</span></div>
              <p className="text-[11px] text-muted-foreground">
                Cible: {c.target_driver_count} chauffeurs · {c.target_completed_rides} courses · Bonus {formatGnf(c.signup_bonus_gnf)} · {c.milestone_rule}
              </p>
              {(c.start_date || c.end_date) && (
                <p className="text-[11px] text-muted-foreground">{c.start_date ?? "—"} → {c.end_date ?? "—"}</p>
              )}
            </div>
          ))}
        </Card>
      )}

      {tab === "contracts" && (
        <Card className="p-3 space-y-2">
          {contracts.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucun contrat enregistré.</p>
          ) : contracts.map(c => (
            <div key={c.id} className="border-b last:border-b-0 border-border/40 pb-2 last:pb-0 text-sm space-y-1">
              <div className="flex justify-between"><p className="font-medium">{c.name}</p><span className="text-[10px] px-1.5 py-0.5 rounded bg-muted">{c.status}</span></div>
              <p className="text-[11px] text-muted-foreground">
                Cibles: {c.target_driver_count} chauffeurs · {c.target_completed_rides} courses · {formatGnf(c.target_gross_earnings_gnf)}
              </p>
              <p className="text-[11px] text-muted-foreground">{c.period_start ?? "—"} → {c.period_end ?? "—"}</p>
            </div>
          ))}
          <p className="text-[10px] text-muted-foreground pt-2 border-t border-border/40">
            Lecture seule. Pour toute modification, contactez l'admin CHOP CHOP.
          </p>
        </Card>
      )}

      {tab === "statements" && (
        <Card className="p-3 space-y-2">
          {statements.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucun relevé finalisé.</p>
          ) : statements.map(s => (
            <div key={s.id} className="flex justify-between items-center text-sm border-b last:border-b-0 border-border/40 pb-2 last:pb-0">
              <div>
                <p className="font-medium">{s.period_start} → {s.period_end}</p>
                <p className="text-[11px] text-muted-foreground">{s.status} · Comm {formatGnf(s.commissions_total_gnf)} · Bonus {formatGnf(s.signup_bonuses_total_gnf)}</p>
              </div>
              <div className="flex items-center gap-2">
                <p className="font-medium tabular-nums">{formatGnf(s.total_due_gnf)}</p>
                {(s.status === "finalized" || s.status === "paid") && (
                  <Button size="sm" variant="outline" onClick={async () => {
                    try {
                      const items = await leaderListMyStatementItems(s.id);
                      downloadStatementCsvRich({
                        filenameStub: `releve-${s.period_start}_${s.period_end}`,
                        periodStart: s.period_start, periodEnd: s.period_end,
                        groupName: group?.name ?? "", leaderLabel: group?.leader_name ?? "",
                        rows: items.map(i => ({ ...i, status: s.status })),
                      });
                    } catch (e: any) {
                      toast({ title: "Erreur export", description: e?.message, variant: "destructive" });
                    }
                  }}>CSV</Button>
                )}
              </div>
            </div>
          ))}
          <p className="text-[10px] text-muted-foreground pt-2 border-t border-border/40">
            Export PDF — à venir (V6). Pour l'instant, utilisez le CSV ou imprimez la page.
          </p>
        </Card>
      )}

      {tab === "checkins" && (
        <Card className="p-3 space-y-2">
          {checkins.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-4">Aucun check-in enregistré.</p>
          ) : checkins.map(c => (
            <CheckinRow key={c.id} c={c} />
          ))}
        </Card>
      )}
    </div>
  );
}

function CheckinForm({ groupId, onSaved }: { groupId: string; onSaved: () => void }) {
  const [type, setType] = useState<string>("field_visit");
  const [notes, setNotes] = useState("");
  const [coords, setCoords] = useState<{ lat?: number; lng?: number; acc?: number }>({});
  const [photo, setPhoto] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);

  const capture = () => {
    if (!navigator.geolocation) { toast({ title: "Géolocalisation indisponible", variant: "destructive" }); return; }
    navigator.geolocation.getCurrentPosition(
      (pos) => setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude, acc: pos.coords.accuracy }),
      () => toast({ title: "Position refusée", description: "Vous pouvez quand même enregistrer sans localisation." }),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  };

  const submit = async () => {
    if (type === "issue_report" && !notes.trim()) {
      toast({ title: "Notes obligatoires pour un signalement", variant: "destructive" }); return;
    }
    setSaving(true);
    try {
      let photo_url: string | null = null;
      if (photo) {
        try { photo_url = await uploadCheckinPhoto(groupId, photo); }
        catch (e: any) { toast({ title: "Photo non envoyée", description: e?.message, variant: "destructive" }); }
      }
      await leaderCreateCheckin({
        group_id: groupId,
        checkin_type: type,
        notes,
        lat: coords.lat, lng: coords.lng, accuracy_m: coords.acc,
        photo_url,
      });
      toast({ title: "Check-in enregistré" });
      onSaved();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message, variant: "destructive" });
    } finally { setSaving(false); }
  };

  return (
    <div className="space-y-3 mt-4">
      <div>
        <label className="text-xs text-muted-foreground">Type</label>
        <select className="w-full mt-1 bg-background border border-border rounded h-9 px-2 text-sm"
          value={type} onChange={e => setType(e.target.value)}>
          <option value="field_visit">Visite terrain</option>
          <option value="recruitment_visit">Recrutement</option>
          <option value="driver_meeting">Réunion chauffeurs</option>
          <option value="market_station">Station marché</option>
          <option value="issue_report">Signalement</option>
          <option value="training">Formation</option>
        </select>
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Notes</label>
        <Textarea value={notes} onChange={e => setNotes(e.target.value)} placeholder="Que s'est-il passé sur le terrain ?" />
      </div>
      <div className="flex items-center justify-between gap-2 text-[11px]">
        <Button size="sm" variant="outline" onClick={capture}>Capturer ma position</Button>
        {coords.lat ? (
          <span className="text-muted-foreground tabular-nums">{coords.lat.toFixed(4)}, {coords.lng!.toFixed(4)}{coords.acc ? ` ±${Math.round(coords.acc)}m` : ""}</span>
        ) : <span className="text-muted-foreground">Position optionnelle</span>}
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Photo (optionnelle, ≤ 5 Mo, jpg/png/webp)</label>
        <input type="file" accept="image/jpeg,image/png,image/webp"
          onChange={e => setPhoto(e.target.files?.[0] ?? null)}
          className="block mt-1 w-full text-xs" />
      </div>
      <Button className="w-full" disabled={saving} onClick={submit}>{saving ? "Envoi…" : "Enregistrer"}</Button>
    </div>
  );
}

function CheckinRow({ c }: { c: FieldCheckin }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (c.photo_url) signedCheckinPhotoUrl(c.photo_url, 600).then(setUrl);
  }, [c.photo_url]);
  return (
    <div className="border-b last:border-b-0 border-border/40 pb-2 last:pb-0 text-sm flex gap-2">
      {url && <a href={url} target="_blank" rel="noreferrer"><img src={url} alt="check-in" loading="lazy" className="w-14 h-14 rounded object-cover border border-border/40" /></a>}
      <div className="flex-1 space-y-1">
        <div className="flex justify-between">
          <p className="font-medium text-[12px]">{c.checkin_type}</p>
          <span className="text-[10px] text-muted-foreground">{new Date(c.created_at).toLocaleString("fr-FR")}</span>
        </div>
        {c.notes && <p className="text-[11px] text-muted-foreground">{c.notes}</p>}
        {(c.lat && c.lng) && (
          <p className="text-[10px] text-muted-foreground tabular-nums">{c.lat.toFixed(5)}, {c.lng.toFixed(5)}</p>
        )}
      </div>
    </div>
  );
}

function Stat({ label, value, icon: Icon }: { label: string; value: string; icon: any }) {
  return (
    <Card className="p-3">
      <div className="flex items-center gap-2 text-muted-foreground text-[10px] uppercase tracking-wider">
        <Icon className="w-3 h-3" /> {label}
      </div>
      <p className="font-semibold tabular-nums mt-1">{value}</p>
    </Card>
  );
}