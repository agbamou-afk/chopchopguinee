import { useEffect, useState } from "react";
import { Loader2, Package, ShieldCheck, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import {
  getCourierPackageView,
  getPackageRuntimeByMission,
  verifyPackageDelivery,
  verifyPackagePickup,
} from "@/lib/packages/api";
import { formatGNF } from "@/lib/format";
import { PACKAGE_TENDER_LABEL, type PackageRuntime } from "@/lib/packages/types";
import type { Mission } from "@/lib/missions/types";

interface Props {
  mission: Mission;
  onVerified?: () => void;
}

/**
 * Courier hand-off panel for `package_delivery` missions.
 *
 * The courier never receives the codes: they are typed in from the sender
 * (pickup) and the recipient (delivery) and validated server-side. State
 * transitions happen inside the RPC, never here.
 */
export function PackageHandoffPanel({ mission, onVerified }: Props) {
  const [pkg, setPkg] = useState<Awaited<ReturnType<typeof getCourierPackageView>>>(null);
  const [runtime, setRuntime] = useState<PackageRuntime | null>(null);
  const [code, setCode] = useState("");
  const [recipient, setRecipient] = useState("");
  const [busy, setBusy] = useState(false);
  const [locked, setLocked] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const v = await getCourierPackageView(mission.id);
        if (alive) setPkg(v);
      } catch { /* mission may not be a package delivery */ }
      const rt = await getPackageRuntimeByMission(mission.id);
      if (alive) setRuntime(rt);
    })();
    return () => { alive = false; };
  }, [mission.id]);

  if (!pkg) return null;

  const phase: "pickup" | "delivery" | "done" =
    mission.state === "delivered"
      ? "done"
      : ["assigned", "heading_to_pickup", "arrived_pickup"].includes(mission.state)
        ? "pickup"
        : "delivery";

  const submit = async () => {
    const clean = code.replace(/\D/g, "");
    if (clean.length < 6) {
      toast.error("Code incomplet.");
      return;
    }
    setBusy(true);
    try {
      const res =
        phase === "pickup"
          ? await verifyPackagePickup(pkg.package_id, clean)
          : await verifyPackageDelivery(pkg.package_id, clean, recipient.trim() || null);

      if (!res.ok) {
        if (res.error === "too_many_attempts") {
          setLocked(true);
          toast.error("Trop de tentatives. Contactez le support.");
        } else {
          const left = res.attempts_left ?? 0;
          if (left <= 0) setLocked(true);
          toast.error(
            left > 0 ? `Code incorrect — ${left} tentative(s) restante(s).` : "Code incorrect.",
          );
        }
        setCode("");
        return;
      }

      toast.success(phase === "pickup" ? "Colis récupéré — code vérifié." : "Remise confirmée.");
      setCode("");
      onVerified?.();
      setRuntime(await getPackageRuntimeByMission(mission.id));
    } catch (e) {
      const msg = (e as { message?: string })?.message ?? "";
      toast.error(
        msg.includes("pickup_not_verified")
          ? "Vérifiez d’abord le code de retrait."
          : msg.includes("invalid_state")
            ? "Cette étape n’est pas disponible pour l’état actuel de la mission."
            : msg.includes("forbidden")
              ? "Cette mission ne vous est pas attribuée."
              : "Vérification impossible.",
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="rounded-xl border border-border p-3 space-y-2.5">
      <div className="flex items-start gap-2">
        <Package className="w-4 h-4 text-primary mt-0.5" />
        <div className="min-w-0">
          <p className="text-[13px] font-semibold text-foreground">Colis {pkg.reference}</p>
          <p className="text-[11.5px] text-muted-foreground leading-snug">
            {pkg.category}
            {pkg.description ? ` · ${pkg.description}` : ""}
            {pkg.handling_notes ? ` · ${pkg.handling_notes}` : ""}
          </p>
          {pkg.is_sandbox && (
            <p className="text-[11px] text-muted-foreground">Mission de test (sandbox).</p>
          )}
        </div>
      </div>

      {runtime && (
        <div className="rounded-lg bg-muted/50 p-2.5 space-y-1">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[12px] text-muted-foreground">Valeur déclarée</span>
            <span className="text-[12.5px] font-semibold text-foreground">
              {formatGNF(runtime.declared_value_gnf)}
            </span>
          </div>
          <div className="flex items-center justify-between gap-2">
            <span className="text-[12px] text-muted-foreground">Caution bloquée</span>
            <span className="text-[12.5px] font-semibold text-foreground">
              {formatGNF(runtime.collateral_gnf)}
            </span>
          </div>
          <div className="flex items-center justify-between gap-2">
            <span className="text-[12px] text-muted-foreground">Paiement</span>
            <span className="text-[12.5px] text-foreground">
              {PACKAGE_TENDER_LABEL[runtime.tender as "cash" | "chop_pay"] ?? runtime.tender}
            </span>
          </div>
          {runtime.cash_due_gnf > 0 && (
            <div className="flex items-center justify-between gap-2">
              <span className="text-[12px] text-muted-foreground">À encaisser en espèces</span>
              <span className="text-[12.5px] font-semibold text-foreground">
                {formatGNF(runtime.cash_due_gnf)}
              </span>
            </div>
          )}
          <p className="text-[11.5px] text-muted-foreground leading-snug flex items-start gap-1.5">
            <ShieldAlert className="w-3.5 h-3.5 mt-0.5 shrink-0" />
            {runtime.picked_up_at
              ? "Le colis est sous votre garde. Votre caution reste bloquée jusqu’à la remise vérifiée."
              : "Dès la vérification du code de retrait, le colis passe sous votre garde et votre caution est engagée."}
          </p>
        </div>
      )}

      {phase === "done" ? (
        <p className="text-[12.5px] text-muted-foreground flex items-center gap-1.5">
          <ShieldCheck className="w-3.5 h-3.5" /> Remise vérifiée et horodatée.
        </p>
      ) : locked ? (
        <p className="text-[12.5px] text-destructive leading-snug">
          Vérification bloquée après trop de tentatives. Contactez le support pour débloquer ce
          colis.
        </p>
      ) : (
        <>
          <p className="text-[12px] text-muted-foreground">
            {phase === "pickup"
              ? "Demandez le code de retrait à l’expéditeur."
              : `Demandez le code de remise à ${pkg.recipient_name}.`}
          </p>
          {phase === "delivery" && (
            <Input
              value={recipient}
              onChange={(e) => setRecipient(e.target.value.slice(0, 120))}
              placeholder="Nom de la personne qui reçoit"
              className="h-11"
            />
          )}
          <div className="flex gap-2">
            <Input
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              placeholder="Code à 6 chiffres"
              inputMode="numeric"
              className="h-11 flex-1 tracking-widest"
              aria-label="Code de vérification"
            />
            <Button className="h-11" onClick={() => void submit()} disabled={busy}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Vérifier"}
            </Button>
          </div>
        </>
      )}
    </div>
  );
}