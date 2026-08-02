import { useState, type ComponentType } from "react";
import { motion } from "framer-motion";
import { ScanLine, Store, LifeBuoy, ChevronRight } from "lucide-react";
import { SteeringWheel } from "@/components/icons/SteeringWheel";
import { useNavigate } from "react-router-dom";
import {
  usePublicPaymentProductName,
  usePublicPaymentProductSubtitle,
} from "@/lib/flags/useFeatureFlag";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import envoyerIcon from "@/assets/icons/envoyer.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import walletIcon from "@/assets/icons/wallet.png";
import scannerIcon from "@/assets/icons/scanner.png";

interface ServicesViewProps {
  /** Reuses the exact same action router as Home. */
  onActionClick: (action: string, params?: { destination?: string }) => void;
}

type ServiceTile = {
  id: string;
  label: string;
  desc: string;
  img?: string;
  Icon?: ComponentType<{ className?: string }>;
  /** Honest unavailable copy when the service is gated off. */
  disabledReason?: string;
  onSelect: () => void;
};

/**
 * Client "Services" destination — the full CHOPCHOP service directory.
 * It is a pure presentation surface: every tile delegates to an existing
 * action (Index.handleAction) or an existing route. No new business logic,
 * no pricing, no wallet mutation.
 */
export function ServicesView({ onActionClick }: ServicesViewProps) {
  const navigate = useNavigate();
  const omName = usePublicPaymentProductName();
  const omSubtitle = usePublicPaymentProductSubtitle();
  const [envoyerOpen, setEnvoyerOpen] = useState(false);

  const tiles: ServiceTile[] = [
    {
      id: "moto",
      label: "Course Moto",
      desc: "Moto-taxi rapide à Conakry",
      img: motoIcon,
      onSelect: () => onActionClick("moto"),
    },
    {
      id: "toktok",
      label: "Course TokTok",
      desc: "Tricycle pour 2 à 3 personnes",
      img: toktokIcon,
      onSelect: () => onActionClick("toktok"),
    },
    {
      id: "envoyer",
      label: "Envoyer",
      desc: "Colis et plis — bientôt dédié",
      img: envoyerIcon,
      onSelect: () => setEnvoyerOpen(true),
    },
    {
      id: "food",
      label: "Repas",
      desc: "Commandez auprès des restaurants",
      img: repasIcon,
      onSelect: () => onActionClick("food"),
    },
    {
      id: "market",
      label: "Marché",
      desc: "Boutiques et annonces près de vous",
      img: marcheIcon,
      onSelect: () => onActionClick("market"),
    },
    {
      id: "wallet",
      label: omName,
      desc: omSubtitle,
      img: walletIcon,
      onSelect: () => onActionClick("wallet"),
    },
    {
      id: "scan",
      label: "Scanner",
      desc: "QR course, paiement ou marchand",
      img: scannerIcon,
      onSelect: () => onActionClick("scan"),
    },
    {
      id: "merchant",
      label: "Devenir marchand",
      desc: "Vendez sur Marché ou Repas",
      Icon: Store,
      onSelect: () => navigate("/devenir-marchand"),
    },
    {
      id: "driver",
      label: "Devenir chauffeur",
      desc: "Roulez avec CHOPCHOP",
      Icon: SteeringWheel,
      onSelect: () => navigate("/driver/apply"),
    },
    {
      id: "help",
      label: "Aide",
      desc: "Support, litiges et FAQ",
      Icon: LifeBuoy,
      onSelect: () => onActionClick("support"),
    },
  ];

  return (
    <div className="max-w-3xl mx-auto pb-6">
      <header className="px-4 pt-[max(1rem,env(safe-area-inset-top))] pb-3">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 className="text-[22px] font-bold tracking-tight text-foreground">Services</h2>
            <p className="text-[13px] text-muted-foreground leading-snug mt-0.5">
              Que voulez-vous faire aujourd’hui ?
            </p>
          </div>
          <button
            type="button"
            onClick={() => onActionClick("scan")}
            aria-label="Scanner un QR CHOPCHOP"
            className="shrink-0 h-11 w-11 rounded-2xl card-warm flex items-center justify-center active:scale-95 transition-transform"
          >
            <ScanLine className="w-5 h-5 text-primary" />
          </button>
        </div>
      </header>

      <div className="px-4 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        {tiles.map((t, i) => {
          const disabled = !!t.disabledReason;
          return (
            <motion.button
              key={t.id}
              type="button"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.24, delay: Math.min(i * 0.025, 0.2), ease: [0.22, 1, 0.36, 1] }}
              whileTap={disabled ? undefined : { scale: 0.985 }}
              onClick={disabled ? undefined : t.onSelect}
              aria-disabled={disabled}
              aria-label={disabled ? `${t.label} — ${t.disabledReason}` : t.label}
              className={`relative flex flex-col items-start gap-2.5 rounded-2xl card-warm p-3.5 min-h-[124px] text-left overflow-hidden transition-shadow ${
                disabled ? "opacity-60" : "active:shadow-soft"
              }`}
            >
              <div className="pointer-events-none absolute inset-x-3 top-0 h-px saffron-seam opacity-70" aria-hidden />
              <div className="w-11 h-11 rounded-xl bg-primary/10 ring-1 ring-primary/15 flex items-center justify-center overflow-hidden shrink-0">
                {t.img ? (
                  <img
                    src={t.img}
                    alt=""
                    aria-hidden
                    loading="lazy"
                    width={1024}
                    height={1024}
                    className="w-11 h-11 object-contain scale-[1.4]"
                  />
                ) : t.Icon ? (
                  <t.Icon className="w-5 h-5 text-primary" />
                ) : null}
              </div>
              <div className="space-y-0.5 min-w-0">
                <p className="text-[13.5px] font-semibold text-foreground leading-tight tracking-tight break-words">
                  {t.label}
                </p>
                <p className="text-[11px] text-muted-foreground leading-snug break-words">
                  {disabled ? t.disabledReason : t.desc}
                </p>
              </div>
            </motion.button>
          );
        })}
      </div>

      {/* Honest interim state for Envoyer until the dedicated parcel module ships. */}
      <Dialog open={envoyerOpen} onOpenChange={setEnvoyerOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Envoyer un colis</DialogTitle>
            <DialogDescription className="space-y-2 text-left">
              <span className="block">
                Le module colis dédié (suivi, preuve de remise, tarif colis) n’est pas encore
                ouvert. Nous ne pouvons donc pas encore le proposer comme service livré.
              </span>
              <span className="block">
                En attendant, vous pouvez réserver une <strong>course moto-coursier</strong> :
                un chauffeur récupère votre pli et le dépose à l’adresse indiquée, au tarif
                course normal.
              </span>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter className="gap-2 sm:gap-2">
            <Button variant="outline" onClick={() => setEnvoyerOpen(false)}>
              Plus tard
            </Button>
            <Button
              onClick={() => {
                setEnvoyerOpen(false);
                onActionClick("moto");
              }}
            >
              Course moto-coursier
              <ChevronRight className="w-4 h-4" />
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
