/**
 * AIService — single client-side entry point for every AI assistant call.
 * All calls go through the `ai-assistant` edge function, which holds the API
 * key, enforces admin-gating, applies rate limits, and writes the audit log.
 *
 * The AI never executes irreversible actions (refund, freeze, price change,
 * outbound message). Every response carries `requiresHumanApproval: true`.
 */
import { supabase } from "@/integrations/supabase/client";

export type AIAction =
  | "admin.summarize"
  | "support.draft_reply"
  | "marche.improve_listing"
  | "fraud.assess";

export interface AICallOptions {
  action: AIAction;
  /** Free-form user prompt (e.g. the question, the ticket text). */
  userPrompt: string;
  /** Structured context the assistant can read but not invent. */
  input?: Record<string, unknown>;
  /** Override the default provider/model. */
  provider?: string;
  model?: string;
}

export interface AIResult<TJson = unknown> {
  ok: true;
  assistant: "admin" | "support" | "marche" | "fraud";
  action: string;
  model: string;
  provider: string;
  text: string;
  json: TJson | null;
  latencyMs: number;
  requiresHumanApproval: true;
}

export interface AIError {
  ok: false;
  error: string;
  status?: number;
}

async function call<TJson = unknown>(
  opts: AICallOptions,
): Promise<AIResult<TJson> | AIError> {
  const { data, error } = await supabase.functions.invoke("ai-assistant", {
    body: opts,
  });
  if (error) {
    const status = (error as any)?.context?.status as number | undefined;
    const message =
      (data as any)?.error || error.message || "Erreur IA inconnue";
    return { ok: false, error: message, status };
  }
  if ((data as any)?.error) {
    return { ok: false, error: (data as any).error };
  }
  return data as AIResult<TJson>;
}

export const AIService = {
  call,

  // ---------- Admin Assistant ----------
  summarizeOps: (
    userPrompt: string,
    context: {
      orders?: unknown;
      rides?: unknown;
      topups?: unknown;
      supportTickets?: unknown;
      walletAlerts?: unknown;
    },
  ) =>
    call<never>({
      action: "admin.summarize",
      userPrompt:
        userPrompt ||
        "Résume l'activité opérationnelle des dernières 24h et identifie les sujets urgents.",
      input: context,
    }),

  // ---------- Support Reply Assistant ----------
  draftSupportReply: (
    ticket: { subject: string; body: string; customerFirstName?: string; locale?: string },
    extraInstruction?: string,
  ) =>
    call<never>({
      action: "support.draft_reply",
      userPrompt:
        extraInstruction ||
        "Rédige un brouillon de réponse empathique à ce ticket. Ne promets rien.",
      input: { ticket },
    }),

  // ---------- Marché Listing Assistant ----------
  improveListing: (listing: {
    title: string;
    description?: string;
    category?: string;
    priceGnf?: number;
  }) =>
    call<{
      title: string;
      description: string;
      warnings: string[];
    }>({
      action: "marche.improve_listing",
      userPrompt:
        "Améliore le titre et la description de cette annonce sans inventer de détails. Liste les informations manquantes dans warnings.",
      input: { listing },
    }),

  // ---------- Fraud / Risk Assistant ----------
  assessRisk: (signals: {
    subjectType: "wallet" | "agent" | "driver" | "marche";
    subjectId: string;
    signals: Record<string, unknown>;
  }) =>
    call<{
      risk: "low" | "medium" | "high";
      reasons: string[];
      suggested_actions: string[];
    }>({
      action: "fraud.assess",
      userPrompt:
        "Évalue le niveau de risque à partir des signaux fournis et propose des actions humaines.",
      input: signals,
    }),
};

export type { AICallOptions as AICall };