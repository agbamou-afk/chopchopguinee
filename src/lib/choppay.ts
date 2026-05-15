/**
 * CHOPPay merchant-QR payload helpers.
 *
 * Two formats are accepted on scan, one is generated:
 *   - URL form  (preferred, human-readable):
 *       chopchop://pay/<merchantId>?amount=25000&name=Le%20Damier
 *     also accepted: choppay://merchant/<merchantId>?amount=25000
 *   - JSON form (legacy / forward-compat):
 *       {"t":"choppay","m":"<merchantId>","a":25000,"n":"Le Damier"}
 *
 * Amount is optional — when absent the client enters it in the payment sheet.
 */

export type ChopPayPayload = {
  merchantId: string;
  amount?: number;
  merchantName?: string;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseChopPayPayload(raw: string): ChopPayPayload | null {
  if (!raw) return null;
  const text = raw.trim();

  // JSON form
  if (text.startsWith("{")) {
    try {
      const o = JSON.parse(text);
      const tag = String(o?.t ?? "").toLowerCase();
      const id = String(o?.m ?? o?.merchant_id ?? "");
      if ((tag === "choppay" || tag === "chopchop-pay") && UUID_RE.test(id)) {
        const a = Number(o?.a ?? o?.amount);
        return {
          merchantId: id,
          amount: Number.isFinite(a) && a > 0 ? Math.floor(a) : undefined,
          merchantName: typeof o?.n === "string" ? o.n : undefined,
        };
      }
    } catch {
      /* fallthrough */
    }
  }

  // URL form — chopchop://pay/<id> or choppay://merchant/<id> or https://...?m=<id>
  try {
    // URL constructor needs a scheme it knows; rewrite custom schemes to https for parsing.
    const normalized = text.replace(/^chopchop:\/\//i, "https://chopchop.local/")
                           .replace(/^choppay:\/\//i, "https://chopchop.local/");
    const u = new URL(normalized);
    const segments = u.pathname.split("/").filter(Boolean);
    // Expected shapes: /pay/<id>  or  /merchant/<id>
    let id = "";
    if (segments[0] === "pay" || segments[0] === "merchant") {
      id = segments[1] ?? "";
    } else if (segments.length === 1) {
      id = segments[0];
    }
    if (!id) id = u.searchParams.get("m") ?? u.searchParams.get("merchant") ?? "";
    if (!UUID_RE.test(id)) return null;
    const a = Number(u.searchParams.get("amount") ?? "");
    return {
      merchantId: id,
      amount: Number.isFinite(a) && a > 0 ? Math.floor(a) : undefined,
      merchantName: u.searchParams.get("name") ?? undefined,
    };
  } catch {
    return null;
  }
}

export function buildChopPayPayload(p: ChopPayPayload): string {
  const params = new URLSearchParams();
  if (p.amount && p.amount > 0) params.set("amount", String(Math.floor(p.amount)));
  if (p.merchantName) params.set("name", p.merchantName);
  const qs = params.toString();
  return `chopchop://pay/${p.merchantId}${qs ? `?${qs}` : ""}`;
}