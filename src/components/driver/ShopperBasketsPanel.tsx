import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import {
  Camera,
  CheckCircle2,
  Loader2,
  MapPin,
  PackageCheck,
  ShoppingBasket,
  Truck,
  XCircle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { formatGNF } from "@/lib/marche";
import {
  arriveAtMarket,
  claimBasket,
  completeDelivery,
  getProcurementMission,
  listAvailableBaskets,
  resolveLine,
  shopperErrorFr,
  startDelivery,
  startShopping,
  submitPurchase,
  uploadPurchaseEvidence,
  LINE_STATE_LABEL_FR,
  MISSION_STATE_LABEL_FR,
  type AvailableBasket,
  type ShopperMission,
  type ShopperMissionLine,
} from "@/lib/marche/shopper";
import { hasCapability } from "@/lib/missions/capabilities";

/**
 * Node 4 R7 — shopper-driver surface.
 *
 * Every button here is a server call. The panel renders the state the server
 * returns; it never advances the mission locally, never computes a spend and
 * never decides whether a purchase is verifiable.
 */
export function ShopperBasketsPanel({
  userId,
  capabilities = [],
}: {
  userId: string | null;
  capabilities?: string[];
}) {
  const eligible = hasCapability(capabilities, "marche_shopper");
  const [queue, setQueue] = useState<AvailableBasket[]>([]);
  const [mission, setMission] = useState<ShopperMission | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

  const reload = useCallback(async () => {
    if (!userId || !eligible) {
      setLoaded(true);
      return;
    }
    try {
      if (activeId) {
        const m = await getProcurementMission(activeId);
        setMission(m);
        if (!m || m.state === "completed" || m.state === "cancelled") setActiveId(null);
      } else {
        setQueue(await listAvailableBaskets(20));
        setMission(null);
      }
    } catch {
      /* server refusals surface on action, not on polling */
    } finally {
      setLoaded(true);
    }
  }, [userId, eligible, activeId]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const run = async (fn: () => Promise<ShopperMission | null>, okMsg?: string) => {
    setBusy(true);
    try {
      const m = await fn();
      if (m && (m as ShopperMission).code === "PROCUREMENT_AUTHORIZATION_REQUIRED") {
        toast.error(
          `${shopperErrorFr("PROCUREMENT_AUTHORIZATION_REQUIRED")} Le client doit autoriser ${formatGNF(
            (m as ShopperMission).required_ceiling_gnf ?? 0,
          )}.`,
        );
      } else if (okMsg) {
        toast.success(okMsg);
      }
      await reload();
    } catch (e) {
      toast.error(shopperErrorFr((e as Error)?.message ?? ""));
    } finally {
      setBusy(false);
    }
  };

  if (!userId || !eligible) return null;

  return (
    <div className="rounded-2xl bg-card border border-border/50 shadow-card p-3 space-y-3">
      <div className="flex items-center gap-2">
        <ShoppingBasket className="w-4 h-4 text-primary" />
        <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground">
          Paniers Marché
        </p>
      </div>

      {!loaded && (
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Loader2 className="w-3.5 h-3.5 animate-spin" /> Chargement…
        </div>
      )}

      {loaded && !mission && queue.length === 0 && (
        <p className="text-[11.5px] text-muted-foreground">
          Aucun panier autorisé disponible pour le moment.
        </p>
      )}

      {loaded && !mission &&
        queue.map((b) => (
          <div key={b.request_id} className="rounded-xl border border-border/60 p-3 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold">
                {b.line_count} article{b.line_count > 1 ? "s" : ""}
              </span>
              <span className="text-sm font-bold">{formatGNF(b.authorized_ceiling_gnf)}</span>
            </div>
            {b.destination_address && (
              <p className="text-[11px] text-muted-foreground flex items-center gap-1">
                <MapPin className="w-3 h-3" /> {b.destination_address}
              </p>
            )}
            <p className="text-[10.5px] text-muted-foreground">
              Montant maximum autorisé par le client. Ne dépassez pas ce plafond.
            </p>
            <Button
              size="sm"
              className="w-full"
              disabled={busy}
              onClick={() =>
                run(async () => {
                  const m = await claimBasket(b.request_id);
                  setActiveId(b.request_id);
                  return m;
                }, "Panier accepté")
              }
            >
              Accepter ce panier
            </Button>
          </div>
        ))}

      {mission && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold text-primary">
              {MISSION_STATE_LABEL_FR[mission.state]}
            </span>
            <span className="text-xs text-muted-foreground">
              Plafond {formatGNF(mission.authorized_ceiling_gnf)}
            </span>
          </div>
          {mission.destination_address && (
            <p className="text-[11px] text-muted-foreground flex items-center gap-1">
              <MapPin className="w-3 h-3" /> {mission.destination_address}
            </p>
          )}

          {mission.state === "assigned" && (
            <Button size="sm" className="w-full" disabled={busy}
              onClick={() => run(() => arriveAtMarket(mission.request_id), "Arrivée au marché")}>
              Je suis au marché
            </Button>
          )}

          {mission.state === "at_market" && (
            <Button size="sm" className="w-full" disabled={busy}
              onClick={() => run(() => startShopping(mission.request_id), "Achats démarrés")}>
              Commencer les achats
            </Button>
          )}

          {mission.state === "shopping" &&
            mission.lines.map((l) => (
              <ShopperLineRow key={l.line_no} line={l} busy={busy}
                onAction={(fn) => run(fn)} requestId={mission.request_id} />
            ))}

          {mission.state === "shopping" && (
            <div className="space-y-2 pt-1">
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  e.target.value = "";
                  if (f) void run(() => uploadPurchaseEvidence(mission.request_id, f), "Reçu ajouté");
                }}
              />
              <Button size="sm" variant="outline" className="w-full" disabled={busy}
                onClick={() => fileRef.current?.click()}>
                <Camera className="w-3.5 h-3.5 mr-1.5" />
                Photo du reçu ({mission.evidence_count})
              </Button>
              <Button size="sm" className="w-full" disabled={busy}
                onClick={() => run(() => submitPurchase(mission.request_id), "Achats vérifiés")}>
                <PackageCheck className="w-3.5 h-3.5 mr-1.5" /> Valider les achats
              </Button>
              <p className="text-[10.5px] text-muted-foreground">
                CHOP CHOP vérifie la dépense réelle. Rien n'est débité au client tant que la
                livraison n'est pas terminée.
              </p>
            </div>
          )}

          {mission.state === "purchase_verified" && (
            <>
              <p className="text-[11px] text-muted-foreground">
                Dépense vérifiée : {formatGNF(mission.verified_spend_gnf ?? 0)}
              </p>
              <Button size="sm" className="w-full" disabled={busy}
                onClick={() => run(() => startDelivery(mission.request_id), "Livraison démarrée")}>
                <Truck className="w-3.5 h-3.5 mr-1.5" /> Démarrer la livraison
              </Button>
            </>
          )}

          {mission.state === "delivering" && (
            <Button size="sm" className="w-full" disabled={busy}
              onClick={() => run(() => completeDelivery(mission.request_id), "Livraison terminée")}>
              <CheckCircle2 className="w-3.5 h-3.5 mr-1.5" /> Marquer livré
            </Button>
          )}
        </div>
      )}
    </div>
  );
}

function ShopperLineRow({
  line,
  requestId,
  busy,
  onAction,
}: {
  line: ShopperMissionLine;
  requestId: string;
  busy: boolean;
  onAction: (fn: () => Promise<ShopperMission | null>) => void;
}) {
  const [price, setPrice] = useState("");
  const [sub, setSub] = useState("");
  const resolved = line.state !== "pending";

  return (
    <div className="rounded-xl border border-border/60 p-3 space-y-2">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-medium truncate">
            {line.commodity_name_fr} · {line.variant_name_fr}
          </p>
          <p className="text-[11px] text-muted-foreground truncate">
            {line.requested_qty} × {line.option_label_fr}
          </p>
        </div>
        <span className="text-[10px] font-semibold text-muted-foreground shrink-0">
          {LINE_STATE_LABEL_FR[line.state]}
        </span>
      </div>

      {line.state === "acquired" && (
        <p className="text-[11px] text-muted-foreground">
          {formatGNF(line.actual_line_total_gnf ?? 0)}
          {line.substitute_label_fr ? ` · ${line.substitute_label_fr}` : ""}
        </p>
      )}
      {line.state === "substitution_proposed" && (
        <p className="text-[11px] text-muted-foreground">
          Proposé au client : {line.pending_proposal?.version ? `v${line.pending_proposal.version} · ` : ""}
          {line.substitute_label_fr ?? "remplacement"} — en attente de sa réponse.
        </p>
      )}

      {!resolved && (
        <div className="space-y-2">
          <Input
            inputMode="numeric"
            placeholder="Prix unitaire réel (GNF)"
            value={price}
            onChange={(e) => setPrice(e.target.value.replace(/\D/g, ""))}
            className="h-9 text-sm"
          />
          <Button
            size="sm"
            className="w-full"
            disabled={busy || !price}
            onClick={() =>
              onAction(() =>
                resolveLine({
                  requestId,
                  lineNo: line.line_no,
                  kind: "acquired",
                  actualUnitPriceGnf: Number(price),
                }),
              )
            }
          >
            Acheté à ce prix
          </Button>
          <Input
            placeholder="Proposer un remplacement au client"
            value={sub}
            onChange={(e) => setSub(e.target.value)}
            className="h-9 text-sm"
          />
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              className="flex-1"
              disabled={busy || !sub.trim()}
              onClick={() =>
                onAction(() =>
                  resolveLine({
                    requestId,
                    lineNo: line.line_no,
                    kind: "propose_substitution",
                    substituteLabelFr: sub.trim(),
                  }),
                )
              }
            >
              Proposer
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="flex-1"
              disabled={busy}
              onClick={() =>
                onAction(() =>
                  resolveLine({ requestId, lineNo: line.line_no, kind: "unavailable" }),
                )
              }
            >
              <XCircle className="w-3.5 h-3.5 mr-1" /> Indisponible
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
