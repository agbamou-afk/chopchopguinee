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
    expected: { missions: 1, completed: 1, failed: 0, wallet: 2, requireDistrictContinuity: true },
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
    expected: { missions: 3, completed: 3, failed: 0, wallet: 9, notifications: 3, requireDistrictContinuity: true },
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
    expected: { missions: 1, completed: 1, failed: 0, wallet: 3, requireDistrictContinuity: true },
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
    expected: { missions: 1, completed: 0, failed: 1, failureReasons: ["client_no_show"] },
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
    expected: { missions: 1, completed: 0, failed: 1, failureReasons: ["courier_rejected"] },
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
    expected: { missions: 1, completed: 0, failed: 1, failureReasons: ["merchant_offline"] },
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
    expected: { missions: 3, completed: 3, failed: 0, wallet: 3 },
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
    expected: { notifications: 5, maxDuplicateNotifications: 1 },
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

// ─────────────────────────────────────────────────────────────────────
// Expanded multi-actor / district / wallet / notification scenarios.
// All scripted, deterministic, in-memory.
// ─────────────────────────────────────────────────────────────────────

SANDBOX_SCENARIOS.push(
  {
    id: "repas_5_simultaneous",
    title: "Repas · 5 commandes simultanées",
    description: "5 clients commandent en parallèle sur 2 restaurants Kaloum.",
    family: "repas",
    expected: { missions: 5, completed: 5, failed: 0, wallet: 15, notifications: 5, requireDistrictContinuity: true },
    async run(ctx) {
      const restos = [
        ctx.spawnActor("restaurant", { label: "Restaurant Damier", district: "Kaloum" }),
        ctx.spawnActor("restaurant", { label: "Restaurant Niger", district: "Kaloum" }),
      ];
      const missions = Array.from({ length: 5 }).map((_, i) => {
        const customer = ctx.spawnActor("customer", { label: `Client #${i + 1}`, district: "Kaloum" });
        const courier = ctx.spawnActor("courier", { label: `Repas-courier ${i + 1}`, district: "Kaloum" });
        const resto = restos[i % restos.length];
        const m = ctx.spawnMission({
          kind: "repas",
          pickupDistrict: "Kaloum",
          dropoffDistrict: i % 2 === 0 ? "Kaloum" : "Dixinn",
          actorIds: [customer.id, resto.id, courier.id],
          amountGnf: REPAS_TICKET,
        });
        ctx.notify(`Nouvelle commande → ${resto.label}`, { refId: m.id });
        return { m, customer, courier, resto };
      });
      await ctx.wait(150);
      for (const { m } of missions) ctx.transitionMission(m.id, "accepted");
      await ctx.wait(200);
      for (const { m } of missions) ctx.transitionMission(m.id, "in_progress");
      await ctx.wait(250);
      for (const { m, customer, courier, resto } of missions) {
        ctx.transitionMission(m.id, "completed");
        ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "receipt", amountGnf: -REPAS_TICKET });
        ctx.walletEntry({ actorId: resto.id, missionId: m.id, kind: "merchant_inflow", amountGnf: Math.round(REPAS_TICKET * 0.75) });
        ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(REPAS_TICKET * 0.15) });
      }
    },
  },
  {
    id: "couriers_compete",
    title: "Moto · 5 couriers en compétition",
    description: "Une offre, 5 couriers — premier accepte, les autres se voient annulés.",
    family: "ride",
    expected: { missions: 5, completed: 1, failed: 4, failureReasons: ["claimed_by_other"], requireDistrictContinuity: true },
    async run(ctx) {
      const rider = ctx.spawnActor("rider", { label: "Rider Kaloum", district: "Kaloum" });
      const couriers = Array.from({ length: 5 }).map((_, i) =>
        ctx.spawnActor("courier", { label: `Moto-${i + 1}`, district: "Kaloum" }),
      );
      const offers = couriers.map((c) =>
        ctx.spawnMission({
          kind: "moto",
          pickupDistrict: "Kaloum",
          dropoffDistrict: "Ratoma",
          actorIds: [rider.id, c.id],
          amountGnf: RIDE_FARE,
        }),
      );
      offers.forEach((m) => ctx.transitionMission(m.id, "dispatched"));
      ctx.notify("Course Kaloum → Ratoma diffusée", { refId: offers[0].id });
      await ctx.wait(180);
      ctx.transitionMission(offers[0].id, "accepted");
      for (let i = 1; i < offers.length; i++) ctx.transitionMission(offers[i].id, "cancelled", { reason: "claimed_by_other" });
      await ctx.wait(300);
      ctx.transitionMission(offers[0].id, "completed");
      ctx.walletEntry({ actorId: rider.id, missionId: offers[0].id, kind: "receipt", amountGnf: -RIDE_FARE });
      ctx.walletEntry({ actorId: couriers[0].id, missionId: offers[0].id, kind: "earning", amountGnf: Math.round(RIDE_FARE * 0.85) });
    },
  },
  {
    id: "marche_chain",
    title: "Marché · chaîne buyer/seller/courier",
    description: "Madina → Dixinn, intérêt acheteur, négo, livraison, paiement.",
    family: "marche",
    expected: { missions: 1, completed: 1, failed: 0, wallet: 3, notifications: 2, requireDistrictContinuity: true },
    async run(ctx) {
      const seller = ctx.spawnActor("seller", { label: "Vendeur Madina", district: "Madina" });
      const buyer = ctx.spawnActor("customer", { label: "Acheteur Dixinn", district: "Dixinn" });
      const courier = ctx.spawnActor("courier", { label: "Marché-courier", district: "Madina" });
      const m = ctx.spawnMission({
        kind: "marche",
        pickupDistrict: "Madina",
        dropoffDistrict: "Dixinn",
        actorIds: [buyer.id, seller.id, courier.id],
        amountGnf: MARCHE_TICKET,
      });
      ctx.notify("Acheteur intéressé", { refId: m.id });
      await ctx.wait(150);
      ctx.notify("Vendeur a accepté l'offre", { refId: m.id });
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "en_route");
      await ctx.wait(250);
      ctx.transitionMission(m.id, "completed");
      ctx.walletEntry({ actorId: buyer.id, missionId: m.id, kind: "receipt", amountGnf: -MARCHE_TICKET });
      ctx.walletEntry({ actorId: seller.id, missionId: m.id, kind: "merchant_inflow", amountGnf: Math.round(MARCHE_TICKET * 0.85) });
      ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(MARCHE_TICKET * 0.1) });
    },
  },
  {
    id: "ride_burst_kaloum",
    title: "Moto · burst haute demande Kaloum",
    description: "8 demandes successives en zone Kaloum, 3 couriers disponibles.",
    family: "ride",
    expected: {
      missions: 8,
      completed: 3,
      failed: 5,
      wallet: 3,
      failureReasons: ["no_courier_available"],
      requireDistrictContinuity: true,
      maxUnresolvedMissions: 0,
      pendingLabel: "expected courier shortage",
    },
    async run(ctx) {
      const couriers = Array.from({ length: 3 }).map((_, i) =>
        ctx.spawnActor("courier", { label: `Moto-K${i + 1}`, district: "Kaloum" }),
      );
      for (let i = 0; i < 8; i++) {
        const rider = ctx.spawnActor("rider", { label: `Demand #${i + 1}`, district: "Kaloum" });
        const m = ctx.spawnMission({
          kind: "moto",
          pickupDistrict: "Kaloum",
          dropoffDistrict: i % 2 ? "Matam" : "Madina",
          actorIds: [rider.id],
          amountGnf: RIDE_FARE,
        });
        ctx.transitionMission(m.id, "dispatched");
        await ctx.wait(60);
        if (i < 3) {
          ctx.transitionMission(m.id, "accepted");
          await ctx.wait(80);
          ctx.transitionMission(m.id, "completed");
          ctx.walletEntry({ actorId: couriers[i].id, missionId: m.id, kind: "earning", amountGnf: Math.round(RIDE_FARE * 0.85) });
        } else {
          ctx.transitionMission(m.id, "timeout", { reason: "no_courier_available" });
          ctx.notify("Aucun courier disponible — file d'attente", { level: "warn", refId: m.id });
        }
      }
    },
  },
  {
    id: "district_mismatch",
    title: "District · mismatch courier",
    description: "Courier préfère Ratoma mais reçoit une mission Matoto — refus poli.",
    family: "failure",
    expected: { missions: 1, completed: 0, failed: 1, failureReasons: ["district_mismatch"] },
    async run(ctx) {
      const courier = ctx.spawnActor("courier", { label: "Moto-Ratoma", district: "Ratoma" });
      const rider = ctx.spawnActor("rider", { label: "Rider Matoto", district: "Matoto" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Matoto",
        dropoffDistrict: "Kaloum",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      ctx.transitionMission(m.id, "dispatched");
      await ctx.wait(150);
      ctx.notify("Mission hors zone préférée", { level: "warn", refId: m.id });
      ctx.transitionMission(m.id, "cancelled", { reason: "district_mismatch" });
    },
  },
  {
    id: "mission_in_your_zone",
    title: "District · mission dans votre zone",
    description: "Courier Kipé reçoit une course Kipé → Ratoma — alerte de zone.",
    family: "notification",
    expected: { missions: 1, completed: 1, failed: 0, notifications: 1, requireDistrictContinuity: true },
    async run(ctx) {
      const courier = ctx.spawnActor("courier", { label: "Moto-Kipé", district: "Kipé" });
      const rider = ctx.spawnActor("rider", { label: "Rider Kipé", district: "Kipé" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Kipé",
        dropoffDistrict: "Ratoma",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      ctx.notify("Mission dans votre zone · Kipé → Ratoma", { refId: m.id });
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "completed");
      ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(RIDE_FARE * 0.9) });
    },
  },
  {
    id: "restaurant_delays_pickup",
    title: "Échec · restaurant retarde pickup",
    description: "Resto accepte, mais le plat n'est pas prêt à l'arrivée du courier.",
    family: "failure",
    expected: { missions: 1, completed: 1, failed: 0, notifications: 1, warnTolerant: true },
    async run(ctx) {
      const resto = ctx.spawnActor("restaurant", { label: "Resto lent", district: "Dixinn" });
      const customer = ctx.spawnActor("customer", { label: "Customer Dixinn", district: "Dixinn" });
      const courier = ctx.spawnActor("courier", { label: "Repas-courier", district: "Dixinn" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Dixinn",
        dropoffDistrict: "Dixinn",
        actorIds: [customer.id, resto.id, courier.id],
        amountGnf: REPAS_TICKET,
      });
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "arrived");
      ctx.notify("Commande non prête — attente", { level: "warn", refId: m.id });
      await ctx.wait(300);
      ctx.transitionMission(m.id, "in_progress");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "completed");
      ctx.walletEntry({ actorId: courier.id, missionId: m.id, kind: "earning", amountGnf: Math.round(REPAS_TICKET * 0.15) });
    },
  },
  {
    id: "merchant_cancels_after_accept",
    title: "Échec · merchant annule après accept",
    description: "Le restaurant annule alors que le courier a déjà accepté.",
    family: "failure",
    expected: { missions: 1, failed: 1, failureReasons: ["merchant_cancelled"], wallet: 1 },
    async run(ctx) {
      const resto = ctx.spawnActor("restaurant", { label: "Resto annulant", district: "Kaloum" });
      const customer = ctx.spawnActor("customer", { label: "Customer Kaloum", district: "Kaloum" });
      const courier = ctx.spawnActor("courier", { label: "Repas-courier", district: "Kaloum" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Kaloum",
        dropoffDistrict: "Kaloum",
        actorIds: [customer.id, resto.id, courier.id],
        amountGnf: REPAS_TICKET,
      });
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(150);
      ctx.notify("Merchant annule la commande", { level: "warn", refId: m.id });
      ctx.transitionMission(m.id, "cancelled", { reason: "merchant_cancelled" });
      ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "refund", amountGnf: REPAS_TICKET });
    },
  },
  {
    id: "missing_dropoff_address",
    title: "Échec · adresse dropoff manquante",
    description: "Mission sans district dropoff — fallback gracieux.",
    family: "failure",
    expected: { missions: 1, failed: 1, failureReasons: ["missing_dropoff"] },
    async run(ctx) {
      const rider = ctx.spawnActor("rider", { label: "Rider sans adresse" });
      const courier = ctx.spawnActor("courier", { label: "Moto-fallback", district: "Ratoma" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Ratoma",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      ctx.transitionMission(m.id, "dispatched");
      await ctx.wait(120);
      ctx.notify("Dropoff manquant — demande info au client", { level: "warn", refId: m.id });
      ctx.transitionMission(m.id, "failed", { reason: "missing_dropoff" });
    },
  },
  {
    id: "customer_unreachable_dropoff",
    title: "Échec · client injoignable au dropoff",
    description: "Le courier arrive au dropoff, le client ne répond pas.",
    family: "failure",
    expected: { missions: 1, failed: 1, failureReasons: ["customer_unreachable"] },
    async run(ctx) {
      const customer = ctx.spawnActor("customer", { label: "Customer absent", district: "Matam" });
      const courier = ctx.spawnActor("courier", { label: "Repas-courier", district: "Matam" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Kaloum",
        dropoffDistrict: "Matam",
        actorIds: [customer.id, courier.id],
        amountGnf: REPAS_TICKET,
      });
      ctx.transitionMission(m.id, "en_route");
      await ctx.wait(200);
      ctx.transitionMission(m.id, "arrived");
      ctx.notify("Client injoignable au dropoff", { level: "warn", refId: m.id });
      await ctx.wait(300);
      ctx.transitionMission(m.id, "failed", { reason: "customer_unreachable" });
    },
  },
  {
    id: "wallet_payment_pending",
    title: "Wallet · paiement en attente",
    description: "Paiement client pending, puis confirmé après délai.",
    family: "wallet",
    expected: { missions: 1, completed: 1, wallet: 3, notifications: 1 },
    async run(ctx) {
      const customer = ctx.spawnActor("customer", { label: "Customer payeur", district: "Kaloum" });
      const merchant = ctx.spawnActor("restaurant", { label: "Resto CHOPPay", district: "Kaloum" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Kaloum",
        dropoffDistrict: "Kaloum",
        actorIds: [customer.id, merchant.id],
        amountGnf: REPAS_TICKET,
      });
      ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "hold", amountGnf: -REPAS_TICKET });
      ctx.notify("Paiement en attente de confirmation", { refId: m.id });
      await ctx.wait(300);
      ctx.transitionMission(m.id, "completed");
      ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "receipt", amountGnf: -REPAS_TICKET });
      ctx.walletEntry({ actorId: merchant.id, missionId: m.id, kind: "merchant_inflow", amountGnf: Math.round(REPAS_TICKET * 0.85) });
    },
  },
  {
    id: "wallet_payment_failed_recovery",
    title: "Wallet · paiement échoué + récupération",
    description: "Premier paiement refusé, second réussit (récupération CHOPPay).",
    family: "wallet",
    expected: { missions: 1, completed: 1, wallet: 4, notifications: 1 },
    async run(ctx) {
      const customer = ctx.spawnActor("customer", { label: "Customer retry", district: "Ratoma" });
      const merchant = ctx.spawnActor("restaurant", { label: "Resto CHOPPay", district: "Ratoma" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Ratoma",
        dropoffDistrict: "Ratoma",
        actorIds: [customer.id, merchant.id],
        amountGnf: REPAS_TICKET,
      });
      ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "hold", amountGnf: -REPAS_TICKET });
      ctx.notify("Paiement refusé — nouvel essai", { level: "warn", refId: m.id });
      await ctx.wait(150);
      ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "refund", amountGnf: REPAS_TICKET });
      await ctx.wait(150);
      ctx.walletEntry({ actorId: customer.id, missionId: m.id, kind: "receipt", amountGnf: -REPAS_TICKET });
      ctx.walletEntry({ actorId: merchant.id, missionId: m.id, kind: "merchant_inflow", amountGnf: Math.round(REPAS_TICKET * 0.85) });
      ctx.transitionMission(m.id, "completed");
    },
  },
  {
    id: "choppay_merchant_inflow",
    title: "Wallet · CHOPPay merchant inflow",
    description: "3 paiements directs CHOPPay reçus par un marchand.",
    family: "wallet",
    expected: { missions: 0, wallet: 6 },
    async run(ctx) {
      const merchant = ctx.spawnActor("restaurant", { label: "Marchand CHOPPay", district: "Madina" });
      for (let i = 0; i < 3; i++) {
        const customer = ctx.spawnActor("customer", { label: `Payeur ${i + 1}`, district: "Madina" });
        ctx.walletEntry({ actorId: customer.id, kind: "receipt", amountGnf: -REPAS_TICKET });
        ctx.walletEntry({ actorId: merchant.id, kind: "merchant_inflow", amountGnf: Math.round(REPAS_TICKET * 0.97) });
        await ctx.wait(80);
      }
    },
  },
  {
    id: "duplicate_delivery_updates",
    title: "Notifications · updates dupliqués",
    description: "Le même update est émis 4 fois — vérifie la déduplication.",
    family: "notification",
    expected: { notifications: 1, maxDuplicateNotifications: 1, missions: 1, completed: 1 },
    async run(ctx) {
      const customer = ctx.spawnActor("customer", { label: "Customer dup", district: "Kipé" });
      const m = ctx.spawnMission({
        kind: "repas",
        pickupDistrict: "Kipé",
        dropoffDistrict: "Kipé",
        actorIds: [customer.id],
        amountGnf: REPAS_TICKET,
      });
      for (let i = 0; i < 4; i++) {
        ctx.notify("Commande en route", { refId: m.id });
        await ctx.wait(40);
      }
      ctx.transitionMission(m.id, "completed");
    },
  },
  {
    id: "courier_accept_then_cancel",
    title: "Échec · courier accepte puis annule",
    description: "Courier accepte la course puis se désiste en route.",
    family: "failure",
    expected: { missions: 2, completed: 1, failed: 1, failureReasons: ["courier_aborted"] },
    async run(ctx) {
      const rider = ctx.spawnActor("rider", { label: "Rider Dixinn", district: "Dixinn" });
      const courier = ctx.spawnActor("courier", { label: "Moto-désiste", district: "Dixinn" });
      const m = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Dixinn",
        dropoffDistrict: "Kaloum",
        actorIds: [rider.id, courier.id],
        amountGnf: RIDE_FARE,
      });
      ctx.transitionMission(m.id, "accepted");
      await ctx.wait(150);
      ctx.transitionMission(m.id, "en_route");
      await ctx.wait(200);
      ctx.notify("Courier annule — réassignation", { level: "warn", refId: m.id });
      ctx.transitionMission(m.id, "cancelled", { reason: "courier_aborted" });
      const backup = ctx.spawnActor("courier", { label: "Moto-backup", district: "Dixinn" });
      const m2 = ctx.spawnMission({
        kind: "moto",
        pickupDistrict: "Dixinn",
        dropoffDistrict: "Kaloum",
        actorIds: [rider.id, backup.id],
        amountGnf: RIDE_FARE,
      });
      ctx.transitionMission(m2.id, "accepted");
      await ctx.wait(200);
      ctx.transitionMission(m2.id, "completed");
      ctx.walletEntry({ actorId: backup.id, missionId: m2.id, kind: "earning", amountGnf: Math.round(RIDE_FARE * 0.85) });
    },
  },
  {
    id: "rapid_mission_alerts",
    title: "Notifications · 5 alertes rapides",
    description: "5 alertes mission consécutives — test du calme UI.",
    family: "notification",
    expected: { missions: 5, failed: 5, notifications: 5, maxDuplicateNotifications: 1, failureReasons: ["auto_decline"] },
    async run(ctx) {
      const courier = ctx.spawnActor("courier", { label: "Moto-stress", district: "Ratoma" });
      for (let i = 0; i < 5; i++) {
        const m = ctx.spawnMission({
          kind: "moto",
          pickupDistrict: "Ratoma",
          dropoffDistrict: i % 2 ? "Kipé" : "Matoto",
          actorIds: [courier.id],
          amountGnf: RIDE_FARE,
        });
        ctx.notify(`Nouvelle mission dispo · ${i + 1}/5`, { refId: m.id });
        await ctx.wait(60);
        ctx.transitionMission(m.id, "timeout", { reason: "auto_decline" });
      }
    },
  },
);