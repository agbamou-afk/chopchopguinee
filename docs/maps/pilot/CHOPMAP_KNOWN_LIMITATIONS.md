# CHOP Maps — Known Limitations (Pilot)

Be transparent with operators and merchants. Do not overpromise.

- **Routing fallback is approximate.** When the provider is unreachable,
  ETA/distance is a haversine + speed-by-mode estimate. The chip displays
  "Estimation approximative".
- **Tronçon table is internal.** `map_fare_troncons` is an observed
  reference for ops; it is not an official published fare.
- **Route observations are learning data only.** Never used for pricing.
- **No automatic trust promotion.** Observed routes stay untrusted until
  an admin reviews them.
- **Pricing engine untouched.** This phase changed nothing in fare,
  wallet, or driver earnings logic.
- **No offline media queue.** Field photos require a live connection.
- **No offline tile downloads.** Tiles are streamed; offline shows the
  `DegradedMapPanel`, not a cached basemap.
- **Customers cannot see idle driver positions.** Only the assigned
  driver of an active ride/mission is visible, and only to that customer.
- **Unverified merchant locations remain "À confirmer".** They are not
  used as the canonical address until admin verification.
- **ETA quality depends on provider availability and road reality.**
  Conakry traffic surges and route closures are not modeled.
- **No service worker background sync yet.** Field drafts require the
  user to manually retry from the drafts list.
- **localStorage cap.** Heavy offline use may evict cached zones/places;
  app falls back to fetch-on-demand.