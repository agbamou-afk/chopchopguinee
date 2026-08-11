import { useCallback, useEffect, useState } from "react";
import { Loader2, Scale } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Card } from "@/components/ui/card";
import { toast } from "sonner";
import { formatGNF } from "@/lib/format";
import { listPackageClaims, resolvePackageClaim } from "@/lib/packages/api";
import {
  PACKAGE_CLAIM_OUTCOME_LABEL,
  type PackageClaimOutcome,
  type PackageRuntime,
} from "@/lib/packages/types";

const OUTCOMES: PackageClaimOutcome[] = [
  "customer_upheld",
  "driver_exonerated",
  "reconciliation_required",
];

/**
 * God-Admin adjudication surface for Envoyer claims (Slice 6).
 * Every money movement is decided server-side by `admin_package_claim_resolve`;
 * this panel only collects the outcome, the reason and the evidence reference.
 */
export function EnvoyerClaimsQueue() {
  const [rows, setRows] = useState<PackageRuntime[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [form, setForm] = useState<
    Record<string, { outcome: PackageClaimOutcome; reason: string; evidence: string; pay: string }>
  >({});

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setRows(await listPackageClaims(true));
    } catch {
      setRows([]);
    }
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const patch = (id: string, next: Partial<{ outcome: PackageClaimOutcome; reason: string; evidence: string; pay: string }>) =>
    setForm((f) => ({
      ...f,
      [id]: { outcome: "driver_exonerated", reason: "", evidence: "", pay: "", ...f[id], ...next },
    }));

  const resolve = async (r: PackageRuntime) => {
    const f = form[r.package_id];
    if (!f) { toast.error("Choisissez une décision."); return; }
    setBusy(r.package_id);
    try {
      await resolvePackageClaim({
        packageId: r.package_id,
        outcome: f.outcome,
        reason: f.reason.trim(),
        evidenceRef: f.evidence.trim(),
        payCustomerGnf: Number(f.pay.replace(/\D/g, "")) || 0,
      });
      toast.success("Réclamation traitée.");
      await load();
    } catch (e) {
      toast.error((e as { message?: string })?.message ?? "Résolution impossible.");
    } finally {
      setBusy(null);
    }
  };

  return (
    <Card className="p-3 mb-4 space-y-3">
      <div className="flex items-center gap-2">
        <Scale className="w-4 h-4 text-primary" />
        <h3 className="text-[13.5px] font-semibold">Réclamations Envoyer</h3>
      </div>

      {loading ? (
        <Loader2 className="w-4 h-4 animate-spin" />
      ) : rows.length === 0 ? (
        <p className="text-[12.5px] text-muted-foreground">Aucune réclamation ouverte.</p>
      ) : (
        rows.map((r) => {
          const f = form[r.package_id];
          return (
            <div key={r.id} className="rounded-xl border border-border p-3 space-y-2">
              <div className="text-[12.5px] text-muted-foreground space-y-0.5">
                <p className="text-foreground font-semibold text-[13px]">Colis {r.package_id.slice(0, 8)}</p>
                <p>Valeur déclarée : {formatGNF(r.declared_value_gnf)}</p>
                <p>
                  Caution coursier : {formatGNF(r.collateral_gnf)} · Exposition plateforme :{" "}
                  {formatGNF(r.claims_exposure_gnf)}
                </p>
                <p>Ouverte le {r.claim_opened_at ? new Date(r.claim_opened_at).toLocaleString("fr-FR") : "—"}</p>
                {r.is_sandbox && <p>Dossier de test (sandbox).</p>}
              </div>

              <div className="flex flex-wrap gap-1.5">
                {OUTCOMES.map((o) => (
                  <button
                    key={o}
                    type="button"
                    onClick={() => patch(r.package_id, { outcome: o })}
                    aria-pressed={f?.outcome === o}
                    className={`text-[11.5px] px-2 py-1 rounded-full border ${
                      f?.outcome === o ? "border-primary bg-primary/10" : "border-border"
                    }`}
                  >
                    {PACKAGE_CLAIM_OUTCOME_LABEL[o]}
                  </button>
                ))}
              </div>

              {f?.outcome === "customer_upheld" && (
                <Input
                  value={f?.pay ?? ""}
                  onChange={(e) => patch(r.package_id, { pay: e.target.value.replace(/\D/g, "") })}
                  placeholder="Montant à indemniser (GNF)"
                  inputMode="numeric"
                  className="h-10"
                />
              )}
              <Input
                value={f?.evidence ?? ""}
                onChange={(e) => patch(r.package_id, { evidence: e.target.value })}
                placeholder="Référence de preuve (dossier, photo, PV…)"
                className="h-10"
              />
              <Textarea
                value={f?.reason ?? ""}
                onChange={(e) => patch(r.package_id, { reason: e.target.value })}
                placeholder="Motif de la décision (obligatoire)"
                className="min-h-[64px]"
              />
              <Button
                size="sm"
                disabled={busy === r.package_id}
                onClick={() => void resolve(r)}
              >
                {busy === r.package_id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : null}
                Enregistrer la décision
              </Button>
            </div>
          );
        })
      )}
      <p className="text-[11px] text-muted-foreground">
        Seul un God Admin peut trancher une réclamation. Le partage caution / exposition plateforme
        est calculé par le serveur.
      </p>
    </Card>
  );
}
