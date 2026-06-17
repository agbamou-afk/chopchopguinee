/**
 * Map Phase 2H — Field visit offline draft queue.
 *
 * Preserves a field agent's in-progress visit form when the connection
 * drops, so they don't lose work. Drafts live in localStorage only and
 * are never auto-submitted on the user's behalf — the agent must
 * explicitly retry.
 *
 * Photos and other media are intentionally NOT queued offline here; this
 * is text/coordinate metadata only. UI should show honest copy.
 */

const KEY = "cc:field_visit_drafts:v1";

export type FieldDraftStatus = "draft" | "pending_retry" | "submitted" | "failed";

export interface FieldVisitDraft {
  id: string;
  pilotId: string;
  payload: Record<string, unknown>;
  status: FieldDraftStatus;
  createdAt: number;
  updatedAt: number;
  lastError?: string | null;
}

function read(): FieldVisitDraft[] {
  try {
    const raw = typeof window !== "undefined" ? window.localStorage.getItem(KEY) : null;
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch { return []; }
}

function write(list: FieldVisitDraft[]) {
  try {
    if (typeof window !== "undefined") window.localStorage.setItem(KEY, JSON.stringify(list));
  } catch { /* quota — ignore */ }
}

export function listDrafts(): FieldVisitDraft[] { return read(); }

export function listPendingDrafts(): FieldVisitDraft[] {
  return read().filter((d) => d.status === "draft" || d.status === "pending_retry" || d.status === "failed");
}

export function saveDraft(input: {
  pilotId: string;
  payload: Record<string, unknown>;
  id?: string;
  status?: FieldDraftStatus;
  lastError?: string | null;
}): FieldVisitDraft {
  const list = read();
  const now = Date.now();
  const id = input.id ?? `fd_${now}_${Math.random().toString(36).slice(2, 8)}`;
  const existingIdx = list.findIndex((d) => d.id === id);
  const draft: FieldVisitDraft = {
    id,
    pilotId: input.pilotId,
    payload: input.payload,
    status: input.status ?? "draft",
    createdAt: existingIdx >= 0 ? list[existingIdx].createdAt : now,
    updatedAt: now,
    lastError: input.lastError ?? null,
  };
  if (existingIdx >= 0) list[existingIdx] = draft; else list.unshift(draft);
  write(list.slice(0, 50));
  return draft;
}

export function markSubmitted(id: string) {
  const list = read().map((d) => d.id === id ? { ...d, status: "submitted" as const, updatedAt: Date.now() } : d);
  // Submitted drafts are auto-pruned to keep storage small.
  write(list.filter((d) => d.status !== "submitted"));
}

export function markFailed(id: string, error: string) {
  const list = read().map((d) =>
    d.id === id ? { ...d, status: "failed" as const, updatedAt: Date.now(), lastError: error } : d,
  );
  write(list);
}

export function removeDraft(id: string) {
  write(read().filter((d) => d.id !== id));
}