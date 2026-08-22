import { type ComponentType } from "react";
import { motion } from "framer-motion";
import { ScanLine, Store, LifeBuoy, Car } from "lucide-react";
import { SteeringWheel } from "@/components/icons/SteeringWheel";
import { useNavigate } from "react-router-dom";
import {
  usePublicPaymentProductName,
  usePublicPaymentProductSubtitle,
  useEnvoyerEnabled,
  useTaxiEnabled,
} from "@/lib/flags/useFeatureFlag";
import { ServiceIcon } from "@/components/services/ServiceIcon";
import { getServiceIconAsset, type IconFamily } from "@/lib/services/serviceIcons";

interface ServicesViewProps {
  /** Reuses the exact same action router as Home. */
  onActionClick: (action: string, params?: { destination?: string }) => void;
}

type ServiceTile = {
  id: string;
  /** Canonical icon id in `@/lib/services/serviceIcons` (Family A only). */
  iconId?: string;
  /** Family A = transactional product, Family B = entry/utility action. */
  family: IconFamily;
  label: string;
  desc: string;
  /** Lucide glyph — Family B always, Family A only as a marked placeholder. */
  Icon?: ComponentType<{ className?: string; strokeWidth?: number }>;
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
  const envoyerOn = useEnvoyerEnabled();
  const taxiOn = useTaxiEnabled();

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
      label: "Course Bonbonna",
      desc: "Plus de place, bagages, abrité de la pluie",
      img: toktokIcon,
      onSelect: () => onActionClick("toktok"),
    },
    {
      id: "auto",
      label: "Course Taxi",
      desc: "Voiture fermée, bagages, tout confort",
      Icon: Car,
      disabledReason: taxiOn ? undefined : "Bientôt disponible",
      onSelect: () => onActionClick("auto"),
    },
    {
      id: "envoyer",
      label: "Envoyer",
      desc: "Documents et petits colis en Guinée",
      img: envoyerIcon,
      disabledReason: envoyerOn ? undefined : "Bientôt disponible",
      onSelect: () => onActionClick("parcel"),
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

    </div>
  );
}
