/**
 * CHOP Sandbox — deterministic scenario library.
 *
 * Scenarios are pure scripted flows: no AI, no randomness beyond ID
 * generation. Each scenario must remain idempotent enough to replay
 * against a fresh engine state without leaking into live runtime.
 */

import type { SandboxScenario } from "./types";

const RIDE_FARE = 18_000;
const REPAS_TICKET = 45_000;
const MARCHE_TICKET = 75_000;

export const SANDBOX_SCENARIOS: SandboxScenario[] = [
  {
    id: "moto_normal",
    title: "Moto · course normale",
    description: "Course Moto Kipé → Ratoma, livrée sans incident, règlement wallet.",
    family: "ride",
    async run(ctx) {
      const rider = ctx.spawnActor("rider", { label: "Rider Kipé", district: "Kipé" });
      const courier = ctx.spawnActor("courier", { label: "Moto-01", district: "Kipé" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Kipé",
        dropoffDistrict: "Ratoma",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      await ctx.wait(150);
      ctx.transitionMission(m.id, "dispatched");
      ctx.notify(`Nouvelle course dispatchée → ${courier.label}`, { refId: m.id });
      await ctx.wait(200);
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "en_route");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "arrived");
      await ctx.wait(150);
      ctx.transitionMission(m.id, "in_progress");
      await ctx.wait(300);
      ctx.transitionMission(m.id, "completed");
      ctx.walletEntry({ actorId: rider.id, missionId: m.id, kind: "receipt", amountGnf: -RIDE_FARE });
      ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(RIDE_FARE * 0.85) });
    },
  },
  {
    id: "repas_lunch_rush",
    title: "Repas · rush midi (3 commandes)",
    description: "Trois commandes Repas successives via le même restaurant Kaloum.",
    family: "repas",
    async run(ctx) {
      const resto = ctx.spawnActor("restaurant", { label: "Restaurant Damier", district: "Kaloum" });
      for (let i = 0; i < 3; i++) {
        const customer = ctx.spawnActor("customer", { label: `Customer #${i + 1}`, district: "Kaloum" });
        const courier = ctx.spawnActor("courier", { label: `Repas-courier ${i + 1}`, district: "Kaloum" });
        const m = ctx.spawnMission({
          kind: "repas",
          pickupDistrict: "Kaloum",
          dropoffDistrict: "Kaloum",
          actorIds: [customer.id, resto.id, courier.id],
          amountGnf: REPAS_TICKET,
        });
        ctx.notify(`Repas commandé → ${resto.label}`, { refId: m.id });
        await ctx.wait(120);
        ctx.transitionMission(m.id, "accepted");
        await ctx.wait(120);
        ctx.transitionMission(m.id, "in_progress");
        await ctx.wait(180);
        ctx.transitionMission(m.id, "completed");
        ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "receipt", amountGnf: -REPAS_TICKET });
        ctx.walletEntry({ actorId: resto.id, missionId: m.id, kind: "merchant_inflow", amountGnf: Math.round(REPAS_TICKET * 0.75) });
        ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(REPAS_TICKET * 0.15) });
      }
    },
  },
  {
    id: "marche_delivery",
    title: "Marché · livraison vendeur",
    description: "Demande de livraison Marché Madina → Ratoma, vendeur prépare, courier livre.",
    family: "marche",
    async run(ctx) {
      const seller = ctx.spawnActor("seller", { label: "Vendeur Madina", district: "Madina" });
      const buyer = ctx.spawnActor("customer", { label: "Acheteur Ratoma", district: "Ratoma" });
      const courier = ctx.spawnActor("courier", { label: "Marché-courier", district: "Madina" });
      const m = ctx.spawnMission({
        kind: "marche",
        pickupDistrict: "Madina",
        dropoffDistrict: "Ratoma",
        actorIds: [buyer.id, seller.id, courier.id],
        amountGnf: MARCHE_TICKET,
      });
      ctx.notify(`Intérêt acheteur → ${seller.label}`, { refId: m.id });
      await ctx.wait(200);
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(250);
      ctx.transitionMission(m.id, "en_route");
      await ctx.wait(300);
      ctx.transitionMission(m.id, "completed");
      ctx.walletEntry({ actorId: buyer.id, missionId: m.id, kind: "receipt", amountGnf: -MARCHE_TICKET });
      ctx.walletEntry({ actorId: seller.id, missionId: m.id, kind: "merchant_inflow", amountGnf: Math.round(MARCHE_TICKET * 0.85) });
      ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(MARCHE_TICKET * 0.1) });
    },
  },
  {
    id: "failed_pickup",
    title: "Échec · pickup raté",
    description: "Le courier arrive mais le client est introuvable.",
    family: "failure",
    async run(ctx) {
      const rider = ctx.spawnActor("rider", { label: "Rider absent", district: "Dixinn" });
      const courier = ctx.spawnActor("courier", { label: "Moto-02", district: "Dixinn" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Dixinn",
        dropoffDistrict: "Matam",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      ctx.transitionMission(m.id, "dispatched");
      await ctx.wait(150);
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "arrived");
      await ctx.wait(300);
      ctx.transitionMission(m.id, "failed", { reason: "client_no_show" });
      ctx.notify("Échec pickup — client introuvable", { level: "warn", refId: m.id });
    },
  },
  {
    id: "courier_rejection",
    title: "Échec · refus courier",
    description: "Le courier reçoit l'offre et la refuse.",
    family: "failure",
    async run(ctx) {
      const rider = ctx.spawnActor("rider", { label: "Rider Matoto", district: "Matoto" });
      const courier = ctx.spawnActor("courier", { label: "Moto-rejet", district: "Matoto" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Matoto",
        dropoffDistrict: "Kaloum",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      ctx.transitionMission(m.id, "dispatched");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "cancelled", { reason: "courier_rejected" });
    },
  },
  {
    id: "merchant_unavailable",
    title: "Échec · merchant hors ligne",
    description: "La commande Repas arrive sur un restaurant indisponible.",
    family: "failure",
    async run(ctx) {
      const resto = ctx.spawnActor("restaurant", { label: "Restaurant fermé", district: "Kaloum" });
      const customer = ctx.spawnActor("customer", { label: "Customer X", district: "Kaloum" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Kaloum",
        dropoffDistrict: "Kaloum",
        actorIds: [customer.id, resto.id],
        amountGnf: REPAS_TICKET,
      });
      await ctx.wait(150);
      ctx.transitionMission(m.id, "failed", { reason: "merchant_offline" });
      ctx.notify("Merchant indisponible", { level: "warn", refId: m.id });
    },
  },
  {
    id: "wallet_continuity",
    title: "Wallet · continuité multi-mission",
    description: "Un même courier accumule 3 gains successifs (continuité ledger).",
    family: "wallet",
    async run(ctx) {
      const courier = ctx.spawnActor("courier", { label: "Moto-loyal", district: "Ratoma" });
      for (let i = 0; i < 3; i++) {
        const rider = ctx.spawnActor("rider", { label: `Client ${i + 1}`, district: "Ratoma" });
        const m = ctx.spawnMission({
          kind: "moto",
          pickupDistrict: "Ratoma",
          dropoffDistrict: "Kipé",
          actorIds: [rider.id, courier.id],
          amountGnf: RIDE_FARE,
        });
        await ctx.wait(100);
        ctx.transitionMission(m.id, "completed");
        ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(RIDE_FARE * 0.85) });
      }
    },
  },
  {
    id: "notification_burst",
    title: "Notifications · rafale",
    description: "Émet 5 notifications variées pour tester la déduplication.",
    family: "notification",
    async run(ctx) {
      const kinds = [
        "Nouvelle course dispo",
        "Repas en préparation",
        "Marché — acheteur intéressé",
        "Wallet rechargé",
        "Mission dans votre zone",
      ];
      for (const k of kinds) {
        ctx.notify(k);
        await ctx.wait(80);
      }
    },
  },
];

export function getScenario(id: string): SandboxScenario | undefined {
  return SANDBOX_SCENARIOS.find((s) => s.id === id);
}