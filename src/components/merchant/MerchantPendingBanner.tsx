import { AlertCircle, Clock, CheckCircle2, XCircle } from "lucide-react";

const COPY: Record<string, { title: string; body: string; icon: React.ComponentType<{ className?: string }>; tone: string }> = {
  draft: {
    title: "Brouillon",
    body: "Complétez les informations puis envoyez votre boutique pour vérification.",
    icon: AlertCircle,
    tone: "bg-muted text-foreground",
  },
  submitted: {
    title: "Boutique en vérification",
    body: "Vous pouvez déjà préparer votre catalogue pendant que notre équipe examine votre boutique.",
    icon: Clock,
    tone: "bg-primary/10 text-foreground",
  },
  in_review: {
    title: "Boutique en vérification",
    body: "Notre équipe examine votre boutique. Vous pouvez préparer votre catalogue.",
    icon: Clock,
    tone: "bg-primary/10 text-foreground",
  },
  needs_info: {
    title: "Informations requises",
    body: "L'équipe CHOPCHOP a besoin d'informations supplémentaires pour finaliser la vérification.",
    icon: AlertCircle,
    tone: "bg-amber-100 text-amber-900",
  },
  rejected: {
    title: "Demande rejetée",
    body: "Votre demande a été rejetée. Contactez le support pour plus d'informations.",
    icon: XCircle,
    tone: "bg-destructive/10 text-destructive",
  },
  approved: {
    title: "Boutique approuvée",
    body: "Votre boutique est en ligne sur Marché.",
    icon: CheckCircle2,
    tone: "bg-emerald-100 text-emerald-900",
  },
};

export function MerchantPendingBanner({ status, reason }: { status: string; reason: string | null }) {
  const meta = COPY[status] ?? COPY.submitted;
  const Icon = meta.icon;
  return (
    <div className={`rounded-2xl p-4 flex items-start gap-3 ${meta.tone}`}>
      <Icon className="w-5 h-5 mt-0.5 shrink-0" />
      <div className="min-w-0">
        <p className="font-semibold text-sm">{meta.title}</p>
        <p className="text-xs leading-snug mt-0.5 opacity-90">{meta.body}</p>
        {reason && (status === "needs_info" || status === "rejected") && (
          <p className="text-xs mt-2 italic opacity-90">« {reason} »</p>
        )}
        <p className="text-[11px] mt-2 opacity-80">
          Vos produits restent privés jusqu'à l'approbation et ne sont pas visibles par les clients.
        </p>
      </div>
    </div>
  );
}