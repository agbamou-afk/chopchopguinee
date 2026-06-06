import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { MapPin, Bell, Camera, ImageIcon, Megaphone, Activity, Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Seo } from "@/components/Seo";
import { SecondaryPageHeader } from "@/components/ui/SecondaryPageHeader";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import { useAuth } from "@/contexts/AuthContext";

type PermState = "granted" | "denied" | "prompt" | "unavailable";

function StatusBadge({ s }: { s: PermState }) {
  const map: Record<PermState, { label: string; cls: string }> = {
    granted: { label: "Autorisé", cls: "bg-emerald-500/15 text-emerald-700" },
    denied: { label: "Refusé", cls: "bg-destructive/15 text-destructive" },
    prompt: { label: "Non demandé", cls: "bg-muted text-muted-foreground" },
    unavailable: { label: "Indisponible", cls: "bg-muted text-muted-foreground" },
  };
  const m = map[s];
  return (
    <span className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${m.cls}`}>{m.label}</span>
  );
}

function useDevicePermission(name: "geolocation" | "notifications" | "camera"): PermState {
  const [state, setState] = useState<PermState>("prompt");
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        if (name === "notifications" && typeof Notification !== "undefined") {
          const p = Notification.permission;
          if (!cancelled) setState(p === "granted" ? "granted" : p === "denied" ? "denied" : "prompt");
          return;
        }
        const perms = (navigator as any).permissions;
        if (!perms?.query) {
          if (!cancelled) setState("unavailable");
          return;
        }
        const res: PermissionStatus = await perms.query({ name: name as PermissionName });
        if (!cancelled) setState((res.state === "prompt" ? "prompt" : res.state) as PermState);
        res.onchange = () => setState((res.state === "prompt" ? "prompt" : res.state) as PermState);
      } catch {
        if (!cancelled) setState("unavailable");
      }
    })();
    return () => { cancelled = true; };
  }, [name]);
  return state;
}

interface PrefsRow {
  allow_urban_insights: boolean;
  allow_marketing_notifications: boolean;
  allow_personalized_offers: boolean;
}

const DEFAULT_PREFS: PrefsRow = {
  allow_urban_insights: true,
  allow_marketing_notifications: false,
  allow_personalized_offers: false,
};

export default function PermissionCenter() {
  const { user, isLoggedIn } = useAuth();
  const loc = useDevicePermission("geolocation");
  const notif = useDevicePermission("notifications");
  const cam = useDevicePermission("camera");
  const [prefs, setPrefs] = useState<PrefsRow>(DEFAULT_PREFS);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!isLoggedIn || !user?.id) { setLoading(false); return; }
    (async () => {
      const { data } = await (supabase as any)
        .from("user_preferences")
        .select("allow_urban_insights, allow_marketing_notifications, allow_personalized_offers")
        .eq("user_id", user.id)
        .maybeSingle();
      if (data) setPrefs(data as PrefsRow);
      setLoading(false);
    })();
  }, [user?.id, isLoggedIn]);

  const update = async (patch: Partial<PrefsRow>) => {
    if (!user?.id) return;
    const next = { ...prefs, ...patch };
    setPrefs(next);
    setSaving(true);
    const { error } = await (supabase as any)
      .from("user_preferences")
      .upsert({ user_id: user.id, ...next }, { onConflict: "user_id" });
    setSaving(false);
    if (error) toast({ title: "Erreur", description: error.message });
  };

  const requestLocation = () => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(() => {}, () => {});
  };
  const requestNotifications = async () => {
    if (typeof Notification === "undefined") return;
    await Notification.requestPermission();
  };

  return (
    <div className="min-h-screen bg-background pb-16">
      <Seo
        title="Permissions & préférences — CHOPCHOP"
        description="Gérez les permissions de votre appareil et vos préférences CHOPCHOP : localisation, notifications, caméra, données urbaines."
        canonical="/settings/permissions"
      />
      <SecondaryPageHeader title="Permissions" onBack={() => window.history.length > 1 ? window.history.back() : window.location.assign("/profile")} />

      <main className="px-4 -mt-5 max-w-md mx-auto space-y-4">
        <section className="bg-card rounded-2xl shadow-card p-4 space-y-3">
          <h2 className="text-sm font-semibold">Permissions appareil</h2>

          <Row icon={<MapPin className="w-4 h-4 text-primary" />} title="Localisation"
            desc="Affiche les services proches, améliore les itinéraires et facilite les livraisons."
            badge={<StatusBadge s={loc} />}
            action={loc !== "granted" && loc !== "unavailable" ? (
              <Button size="sm" variant="outline" onClick={requestLocation}>Activer</Button>
            ) : null}
          />
          <Row icon={<Bell className="w-4 h-4 text-primary" />} title="Notifications"
            desc="Mises à jour de courses, commandes, paiements et support."
            badge={<StatusBadge s={notif} />}
            action={notif !== "granted" && notif !== "unavailable" ? (
              <Button size="sm" variant="outline" onClick={requestNotifications}>Activer</Button>
            ) : null}
          />
          <Row icon={<Camera className="w-4 h-4 text-primary" />} title="Caméra"
            desc="Utilisée uniquement pour scanner les QR codes CHOPCHOP."
            badge={<StatusBadge s={cam} />}
          />
          <Row icon={<ImageIcon className="w-4 h-4 text-primary" />} title="Photos / Documents"
            desc="Uniquement quand vous choisissez d'envoyer une photo ou un document."
            badge={<span className="text-[11px] text-muted-foreground">À la demande</span>}
          />
        </section>

        <section className="bg-card rounded-2xl shadow-card p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">Préférences CHOPCHOP</h2>
            {(saving || loading) && <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />}
          </div>

          <PrefRow
            icon={<Activity className="w-4 h-4 text-primary" />}
            title="Données urbaines agrégées"
            desc="Contribuer aux analyses anonymisées qui améliorent la fiabilité des services à Conakry."
            value={prefs.allow_urban_insights}
            onChange={(v) => update({ allow_urban_insights: v })}
            disabled={!isLoggedIn || loading}
          />
          <PrefRow
            icon={<Bell className="w-4 h-4 text-primary" />}
            title="Notifications marketing"
            desc="Promotions, nouveautés CHOPCHOP. Désactivé par défaut."
            value={prefs.allow_marketing_notifications}
            onChange={(v) => update({ allow_marketing_notifications: v })}
            disabled={!isLoggedIn || loading}
          />
          <PrefRow
            icon={<Megaphone className="w-4 h-4 text-primary" />}
            title="Offres personnalisées"
            desc="Adapter les promotions affichées selon vos commandes récentes."
            value={prefs.allow_personalized_offers}
            onChange={(v) => update({ allow_personalized_offers: v })}
            disabled={!isLoggedIn || loading}
          />

          <div className="rounded-xl bg-muted/40 px-3 py-2 text-[11px] text-muted-foreground">
            CHOPCHOP n'utilise pas le suivi publicitaire inter-apps pour le moment.
          </div>
        </section>

        <section className="bg-card rounded-2xl shadow-card p-4 text-sm space-y-2">
          <h2 className="font-semibold">Légal</h2>
          <Link to="/terms" className="block text-primary">Conditions d'utilisation</Link>
          <Link to="/privacy" className="block text-primary">Politique de confidentialité</Link>
        </section>
      </main>
    </div>
  );
}

function Row({ icon, title, desc, badge, action }: {
  icon: React.ReactNode; title: string; desc: string; badge: React.ReactNode; action?: React.ReactNode;
}) {
  return (
    <div className="flex items-start gap-3 py-2">
      <div className="mt-0.5">{icon}</div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-sm font-semibold text-foreground">{title}</p>
          {badge}
        </div>
        <p className="text-xs text-muted-foreground">{desc}</p>
      </div>
      {action}
    </div>
  );
}

function PrefRow({ icon, title, desc, value, onChange, disabled }: {
  icon: React.ReactNode; title: string; desc: string; value: boolean;
  onChange: (v: boolean) => void; disabled?: boolean;
}) {
  return (
    <div className="flex items-start gap-3 py-2">
      <div className="mt-0.5">{icon}</div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-foreground">{title}</p>
        <p className="text-xs text-muted-foreground">{desc}</p>
      </div>
      <Switch checked={value} onCheckedChange={onChange} disabled={disabled} />
    </div>
  );
}