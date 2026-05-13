import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, ArrowRight, Bike, Car, Package, CheckCircle2, Upload, MapPin, Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useDriverProfile, type DriverVehicle } from "@/hooks/useDriverProfile";
import { toast } from "@/hooks/use-toast";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { cn } from "@/lib/utils";

const VEHICLE_OPTIONS: Array<{ id: DriverVehicle; label: string; sub: string; icon: typeof Bike }> = [
  { id: "moto", label: "Moto", sub: "Course rapide en ville", icon: Bike },
  { id: "toktok", label: "TokTok", sub: "Tricycle, plus de place", icon: Car },
  { id: "livraison", label: "Livraison", sub: "Coursier colis", icon: Package },
];

const ZONES = ["Kaloum", "Dixinn", "Ratoma", "Matam", "Matoto", "Kipé", "Bambeto", "Madina", "Cosa", "Lambanyi", "Sonfonia", "Nongo", "Aéroport"];

export default function DriverApply() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { profile, refetch } = useDriverProfile();
  const [step, setStep] = useState(1);
  const [submitting, setSubmitting] = useState(false);

  const [vehicleType, setVehicleType] = useState<DriverVehicle>(profile?.vehicle_type ?? "moto");
  const [plate, setPlate] = useState(profile?.plate_number ?? "");
  const [zones, setZones] = useState<string[]>(profile?.zones ?? []);
  const [driverPhoto, setDriverPhoto] = useState<string | null>(profile?.driver_photo_url ?? null);
  const [idDoc, setIdDoc] = useState<string | null>(profile?.id_doc_url ?? null);
  const [vehiclePhoto, setVehiclePhoto] = useState<string | null>(profile?.vehicle_photo_url ?? null);

  if (!user) {
    navigate("/auth?redirect=/driver/apply");
    return null;
  }

  const totalSteps = 6;

  const next = () => {
    Analytics.track("driver.application.step", { metadata: { step: step + 1 } });
    setStep((s) => Math.min(s + 1, totalSteps));
  };
  const back = () => setStep((s) => Math.max(s - 1, 1));

  const upload = async (file: File, kind: "driver" | "id" | "vehicle"): Promise<string | null> => {
    if (file.size > 5 * 1024 * 1024) {
      toast({ title: "Fichier trop lourd", description: "Maximum 5 Mo", variant: "destructive" });
      return null;
    }
    const ext = file.name.split(".").pop();
    const path = `${user.id}/${kind}-${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from("driver-docs").upload(path, file, { upsert: true });
    if (error) {
      toast({ title: "Erreur upload", description: error.message, variant: "destructive" });
      return null;
    }
    return path; // store path; signed URL fetched on demand
  };

  const submit = async () => {
    setSubmitting(true);
    Analytics.track("driver.application.submitted", { metadata: { vehicle_type: vehicleType, zones } });
    const { error } = await supabase.rpc("driver_apply", {
      p_payload: {
        vehicle_type: vehicleType,
        plate_number: plate || null,
        driver_photo_url: driverPhoto,
        id_doc_url: idDoc,
        vehicle_photo_url: vehiclePhoto,
        zones,
      },
    });
    setSubmitting(false);
    if (error) {
      toast({ title: "Échec de l'envoi", description: error.message, variant: "destructive" });
      return;
    }
    await refetch();
    toast({ title: "Demande envoyée", description: "Votre demande est en cours de vérification." });
    navigate("/");
  };

  const canNext = (() => {
    if (step === 2) return !!vehicleType;
    if (step === 4) return !!driverPhoto && !!idDoc;
    if (step === 5) return zones.length > 0;
    return true;
  })();

  return (
    <div className="min-h-screen bg-background">
      <header className="sticky top-0 bg-card border-b border-border z-10">
        <div className="max-w-md mx-auto px-4 py-3 flex items-center gap-3">
          <button onClick={() => (step > 1 ? back() : navigate(-1))} className="p-2 -ml-2" aria-label="Retour">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div className="flex-1">
            <p className="text-xs text-muted-foreground">Étape {step}/{totalSteps}</p>
            <h1 className="text-base font-bold text-foreground leading-tight">Devenir chauffeur CHOP CHOP</h1>
          </div>
        </div>
        <div className="h-1 bg-muted">
          <div className="h-1 bg-primary transition-all" style={{ width: `${(step / totalSteps) * 100}%` }} />
        </div>
      </header>

      <main className="max-w-md mx-auto px-4 py-5 pb-32 space-y-4">
        {step === 1 && (
          <Section title="Informations personnelles" sub="Vérifiez vos informations de profil avant de continuer.">
            <div className="rounded-2xl border border-border bg-card p-4 space-y-2 text-sm">
              <Row label="Nom" value={user.user_metadata?.full_name || user.user_metadata?.first_name || "—"} />
              <Row label="Téléphone" value={user.phone || user.user_metadata?.phone || "Aucun"} />
              <Row label="Email" value={user.email ?? "—"} />
            </div>
            <p className="text-xs text-muted-foreground">
              Mettez à jour vos informations dans votre profil si nécessaire avant de soumettre.
            </p>
          </Section>
        )}

        {step === 2 && (
          <Section title="Type de véhicule" sub="Choisissez le type de service que vous souhaitez offrir.">
            <div className="space-y-2">
              {VEHICLE_OPTIONS.map((opt) => (
                <button
                  key={opt.id}
                  onClick={() => setVehicleType(opt.id)}
                  className={cn(
                    "w-full flex items-center gap-3 p-4 rounded-2xl border text-left transition-colors",
                    vehicleType === opt.id ? "border-primary bg-primary/5" : "border-border bg-card",
                  )}
                >
                  <div className={cn("w-11 h-11 rounded-xl flex items-center justify-center", vehicleType === opt.id ? "bg-primary text-primary-foreground" : "bg-muted text-foreground")}>
                    <opt.icon className="w-5 h-5" />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold text-foreground">{opt.label}</p>
                    <p className="text-xs text-muted-foreground">{opt.sub}</p>
                  </div>
                  {vehicleType === opt.id && <CheckCircle2 className="w-5 h-5 text-primary" />}
                </button>
              ))}
            </div>
          </Section>
        )}

        {step === 3 && (
          <Section title="Détails du véhicule" sub="Saisissez la plaque d'immatriculation si vous en avez une.">
            <label className="block">
              <span className="text-xs font-medium text-muted-foreground">Numéro de plaque (optionnel)</span>
              <input
                value={plate}
                onChange={(e) => setPlate(e.target.value.toUpperCase())}
                placeholder="ex. RC-1234-A"
                maxLength={20}
                className="mt-1 w-full h-12 px-4 rounded-2xl border border-border bg-card text-foreground"
              />
            </label>
          </Section>
        )}

        {step === 4 && (
          <Section title="Documents" sub="Photo de profil, pièce d'identité et photo du véhicule (max 5 Mo).">
            <UploadField label="Photo du chauffeur" value={driverPhoto} onChange={(f) => upload(f, "driver").then(setDriverPhoto)} required />
            <UploadField label="Pièce d'identité" value={idDoc} onChange={(f) => upload(f, "id").then(setIdDoc)} required />
            <UploadField label="Photo du véhicule" value={vehiclePhoto} onChange={(f) => upload(f, "vehicle").then(setVehiclePhoto)} />
          </Section>
        )}

        {step === 5 && (
          <Section title="Zones de service" sub="Choisissez où vous souhaitez prendre des courses.">
            <div className="flex flex-wrap gap-2">
              {ZONES.map((z) => {
                const active = zones.includes(z);
                return (
                  <button
                    key={z}
                    onClick={() => setZones((cur) => (active ? cur.filter((x) => x !== z) : [...cur, z]))}
                    className={cn(
                      "inline-flex items-center gap-1 px-3 py-2 rounded-full border text-sm",
                      active ? "bg-primary text-primary-foreground border-primary" : "bg-card text-foreground border-border",
                    )}
                  >
                    <MapPin className="w-3.5 h-3.5" />
                    {z}
                  </button>
                );
              })}
            </div>
          </Section>
        )}

        {step === 6 && (
          <Section title="Vérification" sub="Vérifiez vos informations puis envoyez votre demande.">
            <div className="rounded-2xl border border-border bg-card p-4 space-y-2 text-sm">
              <Row label="Véhicule" value={VEHICLE_OPTIONS.find((v) => v.id === vehicleType)?.label ?? vehicleType} />
              <Row label="Plaque" value={plate || "—"} />
              <Row label="Zones" value={zones.join(", ") || "—"} />
              <Row label="Photo chauffeur" value={driverPhoto ? "Téléversée" : "Manquante"} />
              <Row label="Pièce d'identité" value={idDoc ? "Téléversée" : "Manquante"} />
              <Row label="Photo véhicule" value={vehiclePhoto ? "Téléversée" : "Optionnel"} />
            </div>
            <p className="text-xs text-muted-foreground">
              En soumettant, vous acceptez les conditions chauffeur de CHOP CHOP. Votre dossier sera examiné sous 24-48 h.
            </p>
          </Section>
        )}
      </main>

      <footer className="fixed bottom-0 inset-x-0 bg-card border-t border-border safe-area">
        <div className="max-w-md mx-auto px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          {step < totalSteps ? (
            <button
              onClick={next}
              disabled={!canNext}
              className="w-full h-12 rounded-2xl bg-primary text-primary-foreground font-semibold inline-flex items-center justify-center gap-2 disabled:opacity-50"
            >
              Continuer <ArrowRight className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={submit}
              disabled={submitting}
              className="w-full h-12 rounded-2xl bg-primary text-primary-foreground font-semibold inline-flex items-center justify-center gap-2 disabled:opacity-60"
            >
              {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
              Envoyer ma demande
            </button>
          )}
        </div>
      </footer>
    </div>
  );
}

function Section({ title, sub, children }: { title: string; sub?: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <div>
        <h2 className="text-lg font-bold text-foreground">{title}</h2>
        {sub && <p className="text-sm text-muted-foreground">{sub}</p>}
      </div>
      {children}
    </section>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium text-foreground text-right truncate max-w-[60%]">{value}</span>
    </div>
  );
}

function UploadField({
  label,
  value,
  onChange,
  required,
}: {
  label: string;
  value: string | null;
  onChange: (file: File) => void;
  required?: boolean;
}) {
  return (
    <label className="flex items-center gap-3 p-3 rounded-2xl border border-border bg-card cursor-pointer">
      <div className={cn("w-10 h-10 rounded-xl flex items-center justify-center", value ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground")}>
        {value ? <CheckCircle2 className="w-5 h-5" /> : <Upload className="w-5 h-5" />}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-foreground">
          {label} {required && <span className="text-destructive">*</span>}
        </p>
        <p className="text-xs text-muted-foreground truncate">
          {value ? value.split("/").pop() : "Toucher pour téléverser"}
        </p>
      </div>
      <input
        type="file"
        accept="image/*,application/pdf"
        className="hidden"
        onChange={(e) => e.target.files?.[0] && onChange(e.target.files[0])}
      />
    </label>
  );
}