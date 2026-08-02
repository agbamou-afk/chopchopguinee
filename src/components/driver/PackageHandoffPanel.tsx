import { useEffect, useState } from "react";
import { Loader2, Package, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import {
  getCourierPackageView,
  verifyPackageDelivery,
  verifyPackagePickup,
} from "@/lib/packages/api";
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
  const [code, setCode] = useState("");
  const [recipient, setRecipient] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const v = await getCourierPackageView(mission.id);
        if (alive) setPkg(v);
      } catch { /* mission may not be a package delivery */ }
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
    if (clean.length < 4) {
      toast.error("Code incomplet.");
      return;
    }
    setBusy(true);
    try {
      if (phase === "pickup") {
        await verifyPackagePickup(pkg.package_id, clean);
        toast.success("Colis récupéré — code vérifié.");
      } else {
        await verifyPackageDelivery(pkg.package_id, clean, recipient.trim() || null);
        toast.success("Remise confirmée.");
      }
      setCode("");
      onVerified?.();
    } catch (e) {
      const msg = (e as { message?: string })?.message ?? "";
      toast.error(
        msg.includes("invalid_code")
          ? "Code incorrect."
          : msg.includes("too_many_attempts")
            ? "Trop de tentatives. Contactez le support."
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

      {phase === "done" ? (
        <p className="text-[12.5px] text-muted-foreground flex items-center gap-1.5">
          <ShieldCheck className="w-3.5 h-3.5" /> Remise vérifiée et horodatée.
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