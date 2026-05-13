/**
 * CHOP CHOP — Event taxonomy.
 * Standard format: `category.action.object`
 *
 * NEVER fire an event whose name is not in this file. Add it here first so
 * the admin dashboards and AI insights stay coherent across the codebase.
 */

export const EVENTS = {
  // --- Auth ---
  "auth.signup.started": "auth",
  "auth.signup.completed": "auth",
  "auth.login.started": "auth",
  "auth.login.completed": "auth",
  "auth.logout.completed": "auth",

  // --- Session / app shell ---
  "app.session.opened": "session",
  "app.session.closed": "session",
  "app.screen.viewed": "session",
  "app.error.encountered": "session",
  "app.empty_state.viewed": "session",
  "app.permission.requested": "session",
  "app.permission.granted": "session",
  "app.permission.denied": "session",

  // --- Smart Search / Command Bar ---
  "search.command.opened": "search",
  "search.command.submitted": "search",
  "search.command.no_result": "search",
  "search.result.clicked": "search",
  "search.ai.fallback_used": "search",

  // --- Day 4 Home / CommandBar surface ---
  "home.viewed": "session",
  "home.primary_action.clicked": "session",
  "commandbar.opened": "search",
  "commandbar.query.submitted": "search",
  "commandbar.intent.detected": "search",
  "commandbar.result.clicked": "search",
  "commandbar.no_results": "search",
  "search.routed_to_service": "search",

  // --- Mobility ---
  "moto.booking.started": "moto",
  "moto.booking.completed": "moto",
  "moto.booking.cancelled": "moto",
  "toktok.booking.started": "toktok",
  "toktok.booking.completed": "toktok",
  "toktok.booking.cancelled": "toktok",

  // --- Food / Repas ---
  "repas.page.viewed": "repas",
  "repas.restaurant.viewed": "repas",
  "repas.cart.added": "repas",
  "repas.cart.abandoned": "repas",
  "repas.checkout.started": "repas",
  "repas.order.placed": "repas",
  "repas.order.delivered": "repas",

  // --- Marché ---
  "marche.page.viewed": "marche",
  "marche.listing.viewed": "marche",
  "marche.listing.saved": "marche",
  "marche.listing.created": "marche",
  "marche.listing.reported": "marche",
  "marche.seller.contacted": "marche",

  // --- Envoyer (parcel) ---
  "envoyer.flow.started": "envoyer",
  "envoyer.flow.completed": "envoyer",
  "envoyer.flow.abandoned": "envoyer",

  // --- Wallet ---
  "wallet.viewed": "wallet",
  "wallet.topup.started": "wallet",
  "wallet.topup.completed": "wallet",
  "wallet.topup.failed": "wallet",
  "wallet.payment.completed": "wallet",
  "wallet.payment.failed": "wallet",
  "wallet.pin.failed": "wallet",

  // --- Driver ---
  "driver.online": "driver",
  "driver.offline": "driver",
  "driver.ride.accepted": "driver",
  "driver.ride.declined": "driver",
  "driver.ride.completed": "driver",
  "driver.application.step": "driver",
  "driver.application.submitted": "driver",
  "driver.application.approved": "driver",
  "driver.application.rejected": "driver",
  "driver.cash.over_limit": "driver",
  "driver.cash.settle.requested": "driver",
  "driver.support.opened": "driver",

  // --- Agent (top-up vendor) ---
  "agent.topup.created": "agent",
  "agent.topup.confirmed": "agent",
  "agent.float.low": "agent",

  // --- Support ---
  "support.opened": "support",
  "support.ticket.created": "support",

  // --- Risk (always-on, not gated by basic_analytics consent) ---
  "risk.signal.detected": "risk",
} as const;

export type EventName = keyof typeof EVENTS;

/** Risk-related events that are always logged regardless of consent. */
export const ALWAYS_ON_EVENTS = new Set<string>([
  "risk.signal.detected",
  "auth.login.started",
  "auth.login.completed",
  "auth.signup.started",
  "auth.signup.completed",
  "wallet.pin.failed",
  "wallet.payment.failed",
  "wallet.topup.failed",
]);

export function categoryFor(name: EventName | string): string {
  return (EVENTS as Record<string, string>)[name] ?? "other";
}