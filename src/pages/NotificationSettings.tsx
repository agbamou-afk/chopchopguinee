import { useNavigate } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { AppShell } from "@/components/ui/AppShell";
import { PageHeader } from "@/components/ui/PageHeader";
import { Switch } from "@/components/ui/switch";
import { useNotificationPreferences } from "@/lib/messaging";
import { Seo } from "@/components/Seo";

const channels = [
  { key: "whatsapp_enabled", label: "WhatsApp", help: "Canal principal — gratuit pour le destinataire." },
  { key: "sms_enabled", label: "SMS", help: "Canal de secours si WhatsApp échoue." },
] as const;

const topics: { key: "topic_otp" | "topic_wallet" | "topic_ride" | "topic_marketing"; label: string; help?: string }[] = [
  { key: "topic_otp", label: "Codes de vérification (OTP)", help: "Toujours recommandé." },
  { key: "topic_wallet", label: "CHOPWallet (recharges, paiements)" },
  { key: "topic_ride", label: "Courses & livraisons" },
  { key: "topic_marketing", label: "Promotions & nouveautés" },
];

const NotificationSettings = () => {
  const navigate = useNavigate();
  const { prefs, save, loading, userId } = useNotificationPreferences();

  return (
    <AppShell>
      <Seo
        title="Préférences de notifications — CHOP CHOP"
        description="Choisissez comment recevoir vos messages CHOP CHOP : WhatsApp, SMS, et types d'alertes."
        canonical="/settings/notifications"
      />
      <PageHeader title="Notifications" subtitle="Canaux et types d'alertes" onBack={() => navigate(-1)} />

      {loading ? (
        <div className="flex justify-center py-20">
          <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
        </div>
      ) : !userId ? (
        <div className="px-4 py-12 text-center text-sm text-muted-foreground">
          Connectez-vous pour gérer vos préférences.
        </div>
      ) : (
        <div className="px-4 space-y-6 pt-2">
          <section>
            <h2 className="text-xs font-semibold text-muted-foreground uppercase mb-2">Canal préféré</h2>
            <div className="bg-card rounded-2xl shadow-card p-1 flex">
              {(["whatsapp", "sms"] as const).map((c) => (
                <button
                  key={c}
                  onClick={() => save({ preferred_channel: c })}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-medium transition ${
                    prefs.preferred_channel === c
                      ? "bg-primary text-primary-foreground"
                      : "text-muted-foreground"
                  }`}
                >
                  {c === "whatsapp" ? "WhatsApp" : "SMS"}
                </button>
              ))}
            </div>
            <p className="text-[11px] text-muted-foreground mt-2">
              Si le canal préféré échoue, l'autre sert de secours automatique.
            </p>
          </section>

          <section>
            <h2 className="text-xs font-semibold text-muted-foreground uppercase mb-2">Canaux activés</h2>
            <div className="bg-card rounded-2xl shadow-card divide-y divide-border">
              {channels.map((c) => (
                <div key={c.key} className="flex items-center justify-between p-4">
                  <div className="min-w-0 pr-4">
                    <p className="font-medium text-foreground text-sm">{c.label}</p>
                    <p className="text-xs text-muted-foreground">{c.help}</p>
                  </div>
                  <Switch
                    checked={prefs[c.key]}
                    onCheckedChange={(v) => save({ [c.key]: v } as never)}
                  />
                </div>
              ))}
            </div>
          </section>

          <section>
            <h2 className="text-xs font-semibold text-muted-foreground uppercase mb-2">Types d'alertes</h2>
            <div className="bg-card rounded-2xl shadow-card divide-y divide-border">
              {topics.map((t) => (
                <div key={t.key} className="flex items-center justify-between p-4">
                  <div className="min-w-0 pr-4">
                    <p className="font-medium text-foreground text-sm">{t.label}</p>
                    {t.help && <p className="text-xs text-muted-foreground">{t.help}</p>}
                  </div>
                  <Switch
                    checked={prefs[t.key]}
                    onCheckedChange={(v) => save({ [t.key]: v } as never)}
                    disabled={t.key === "topic_otp"}
                  />
                </div>
              ))}
            </div>
          </section>
        </div>
      )}
    </AppShell>
  );
};

export default NotificationSettings;
