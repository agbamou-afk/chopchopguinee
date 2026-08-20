import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

const rpcMock = vi.fn();
vi.mock("@/integrations/supabase/client", () => ({
  supabase: { rpc: (...a: unknown[]) => rpcMock(...a) },
}));

import { ReputationBadge } from "@/components/marche/ReputationBadge";
import {
  DIMENSION_LABEL_FR,
  dimensionLabelFr,
  getReputationSummary,
  reputationDisplay,
  reputationErrorFr,
  submitReputation,
  SUBJECT_LABEL_FR,
  type ReputationSummary,
} from "@/lib/marche/reputation";

const summary: ReputationSummary = {
  subject_kind: "merchant_store",
  subject_id: "s1",
  has_reputation: true,
  rating_count: 2,
  overall_average: 4,
  last_rated_at: new Date().toISOString(),
  dimensions: [{ dimension: "quality", average: 3, count: 2 }],
};

beforeEach(() => rpcMock.mockReset());

describe("R9 client never authors reputation truth", () => {
  it("sends only transaction, subject kind, score, comment and dimensions", async () => {
    rpcMock.mockResolvedValue({ data: { event_id: "e1", status: "RECORDED" }, error: null });
    await submitReputation({
      transactionKind: "merchant_order",
      transactionId: "o1",
      subjectKind: "merchant_store",
      overallScore: 5,
      comment: "  ok  ",
      dimensions: { quality: 4 },
    });
    const payload = rpcMock.mock.calls[0][1].p_payload as Record<string, unknown>;
    expect(Object.keys(payload).sort()).toEqual(
      ["comment", "dimensions", "overall_score", "subject_kind", "transaction_id", "transaction_kind"],
    );
    expect(payload.comment).toBe("ok");
    expect(payload).not.toHaveProperty("subject_user_id");
    expect(payload).not.toHaveProperty("subject_store_id");
    expect(payload).not.toHaveProperty("rating_count");
    expect(payload).not.toHaveProperty("overall_average");
  });

  it("omits empty comment and empty dimension maps entirely", async () => {
    rpcMock.mockResolvedValue({ data: { event_id: "e1", status: "RECORDED" }, error: null });
    await submitReputation({
      transactionKind: "procurement",
      transactionId: "r1",
      subjectKind: "shopper",
      overallScore: 3,
      comment: "   ",
      dimensions: {},
    });
    const payload = rpcMock.mock.calls[0][1].p_payload as Record<string, unknown>;
    expect(payload).not.toHaveProperty("comment");
    expect(payload).not.toHaveProperty("dimensions");
  });

  it("reads aggregates from the server RPC only", async () => {
    rpcMock.mockResolvedValue({ data: summary, error: null });
    const s = await getReputationSummary("merchant_store", "s1");
    expect(rpcMock).toHaveBeenCalledWith("marche_reputation_summary", {
      p_subject_kind: "merchant_store",
      p_subject_id: "s1",
    });
    expect(s.overall_average).toBe(4);
  });
});

describe("R9 honest display law", () => {
  it("never invents a score for an unrated subject", () => {
    const v = reputationDisplay({ ...summary, has_reputation: false, rating_count: 0, overall_average: null });
    expect(v.hasReputation).toBe(false);
    expect(v.scoreLabel).toBe("Pas encore noté");
  });

  it("renders the server average and verified count, never a computed one", async () => {
    rpcMock.mockResolvedValue({ data: summary, error: null });
    render(<ReputationBadge subjectKind="merchant_store" subjectId="s1" />);
    await waitFor(() => expect(screen.getByText(/4,00 \/ 5/)).toBeInTheDocument());
    expect(screen.getByText(/2 notes vérifiées/)).toBeInTheDocument();
  });

  it("states plainly when a subject has no verified rating yet", async () => {
    rpcMock.mockResolvedValue({
      data: { ...summary, has_reputation: false, rating_count: 0, overall_average: null, dimensions: [] },
      error: null,
    });
    render(<ReputationBadge subjectKind="delivery_driver" subjectId="d1" />);
    await waitFor(() => expect(screen.getByText("Pas encore noté")).toBeInTheDocument());
  });
});

describe("R9 vocabulary is complete and French", () => {
  it("labels every subject kind", () => {
    expect(Object.keys(SUBJECT_LABEL_FR).sort()).toEqual(
      ["delivery_driver", "merchant_store", "shopper"],
    );
  });

  it("labels every server dimension across the three roles", () => {
    const server = [
      "quality", "accuracy", "availability", "packaging", "preparation", "value",
      "courtesy", "communication", "timeliness", "order_care",
      "selection_quality", "freshness", "substitution_quality", "shopping_accuracy",
    ];
    server.forEach((d) => expect(DIMENSION_LABEL_FR[d]).toBeTruthy());
    expect(dimensionLabelFr("unknown_dimension")).toBe("unknown_dimension");
  });

  it("translates the machine-readable refusals a customer can hit", () => {
    expect(reputationErrorFr("TRANSACTION_NOT_COMPLETED")).toMatch(/terminée/);
    expect(reputationErrorFr("NOT_AUTHORIZED")).toMatch(/client/);
    expect(reputationErrorFr("CLIENT_SUBJECT_NOT_ALLOWED")).toMatch(/CHOP CHOP/);
    expect(reputationErrorFr("REPUTATION_IMMUTABLE")).toMatch(/définitive|modifiée/);
  });
});