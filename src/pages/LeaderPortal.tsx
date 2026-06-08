import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/AuthContext";
import Seo from "@/components/Seo";
import {
  leaderGetMyGroup, leaderListMyMembers, leaderListMyCommissions,
  leaderListMyReferrals, leaderGetMyStats, type LeaderMember,
} from "@/lib/leader/driverGroup";
import { formatGnf, type DriverGroup, type DriverGroupCommission, type DriverReferral, type DriverGroupStats } from "@/lib/admin/driverGroups";
import { Users2, Coins, Gift, Map as MapIcon, ArrowLeft } from "lucide-react";

type Tab = "overview" | "drivers" | "commissions" | "referrals";

export default function LeaderPortal() {
  const { user, loading: authLoading } = useAuth();
  const navigate = useNavigate();
  const [tab, setTab] = useState<Tab>("overview");
  const [group, setGroup] = useState<DriverGroup | null>(null);
  const [members, setMembers] = useState<LeaderMember[]>([]);
  const [commissions, setCommissions] = useState<DriverGroupCommission[]>([]);
  const [referrals, setReferrals] = useState<DriverReferral[]>([]);
  const [stats, setStats] = useState<DriverGroupStats | null>(null);
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
        const [m, c, r, s] = await Promise.all([
          leaderListMyMembers(), leaderListMyCommissions(), leaderListMyReferrals(), leaderGetMyStats(30),
        ]);
        if (cancel) return;
        setMembers(m); setCommissions(c); setReferrals(r); setStats(s);
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

      {isSuspended && (
        <Card className="p-3 text-sm bg-destructive/10 text-destructive border-destructive/30">
          Ce groupe est suspendu. Aucune nouvelle commission ne sera calculée jusqu'à réactivation par CHOP CHOP.
        </Card>
      )}

      <div className="flex flex-wrap gap-2">
        {([
          ["overview", "Vue d'ensemble"],
          ["drivers", `Chauffeurs (${members.filter(m => m.status === "active").length})`],
          ["commissions", `Commissions (${commissions.length})`],
          ["referrals", `Parrainages (${referrals.length})`],
        ] as [Tab, string][]).map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
            className={`px-3 py-1.5 text-xs rounded-full border ${tab === k ? "bg-primary text-primary-foreground border-primary" : "bg-background border-border text-muted-foreground"}`}>
            {l}
          </button>
        ))}
      </div>

      {tab === "overview" && (
        <div className="grid grid-cols-2 gap-2">
          <Stat label="Chauffeurs actifs" value={String(stats?.active_drivers ?? 0)} icon={Users2} />
          <Stat label="Courses 30j" value={String(stats?.rides_completed ?? 0)} icon={Coins} />
          <Stat label="Commissions en attente" value={formatGnf(stats?.commissions_pending_gnf ?? 0)} icon={Coins} />
          <Stat label="Commissions payées 30j" value={formatGnf(stats?.commissions_paid_gnf ?? 0)} icon={Coins} />
          <Stat label="Parrainages éligibles" value={String(stats?.signup_bonus_eligible_count ?? 0)} icon={Gift} />
          <Stat label="Bonus payés 30j" value={formatGnf(stats?.signup_bonus_paid_gnf ?? 0)} icon={Gift} />
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