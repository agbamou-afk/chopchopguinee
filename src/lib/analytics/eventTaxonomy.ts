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
  "wallet.history.viewed": "wallet",
  "wallet.empty_state.viewed": "wallet",
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
  "driver.search.reassurance.shown": "driver",
  "driver.application.step": "driver",
  "driver.application.submitted": "driver",
  "driver.application.approved": "driver",
  "driver.application.rejected": "driver",
  "driver.cash.over_limit": "driver",
  "driver.cash.settle.requested": "driver",
  "driver.support.opened": "driver",

  // --- Onboarding & retention ---
  "onboarding.viewed": "session",
  "onboarding.step.viewed": "session",
  "onboarding.completed": "session",
  "onboarding.skipped": "session",
  "home.welcome_back.viewed": "session",
  "ride.connection.restored": "session",
  "client.ride.completed": "session",

  // --- Trust & Retention (Pass 2) ---
  "ride.trust_message_viewed": "session",
  "driver.trust_message_viewed": "driver",
  "receipt.viewed": "session",

  // --- CHOPPay merchant QR ---
  "qr.payment_sheet_opened": "wallet",
  "qr.payment_confirmed": "wallet",
  "qr.payment_cancelled": "wallet",
  "qr.payment_failed": "wallet",
  "qr.scan_invalid": "wallet",
  "qr.scan_success": "wallet",
  "merchant.qr_viewed": "wallet",
  "receipt.qr_payment_viewed": "wallet",
  "merchant.payment_completed": "wallet",
  "merchant.receipt_viewed": "wallet",
  "merchant.repeat_interaction": "wallet",
  "wallet.balance_updated_after_payment": "wallet",

  // --- Maps / routing / location (Day 6) ---
  "map.loaded": "map",
  "map.load.failed": "map",
  "route.requested": "map",
  "route.calculated": "map",
  "route.success": "map",
  "route.failed": "map",
  "eta.calculated": "map",
  "pickup.adjusted": "map",
  "driver.search.started": "map",
  "driver.search.matched": "map",
  "driver.search.failed": "map",
  "location.permission.requested": "map",
  "location.permission.granted": "map",
  "location.permission.denied": "map",
  "location.low_accuracy": "map",
  "saved_place.created": "map",
  "saved_place.used": "map",
  "saved_place.deleted": "map",

  // --- Day 6 perf + field testing ---
  "map.perf.fps": "map",
  "map.perf.degraded": "map",
  "field.test.started": "map",
  "field.test.checkpoint": "map",
  "field.test.note": "map",
  "field.test.completed": "map",

  // --- Agent (top-up vendor) ---
  "agent.topup.created": "agent",
  "agent.topup.confirmed": "agent",
  "agent.float.low": "agent",

  // --- Support ---
  "support.opened": "support",
  "support.ticket.created": "support",

  // --- Notifications (delivery reliability) ---
  "notification.sent": "notification",
  "notification.failed": "notification",
  "notification.opened": "notification",
  "notification.queued_offline": "notification",
  "whatsapp.fallback.used": "notification",

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
  "notification.failed",
  "whatsapp.fallback.used",
]);

export function categoryFor(name: EventName | string): string {
  return (EVENTS as Record<string, string>)[name] ?? "other";
}