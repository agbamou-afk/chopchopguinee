/**
 * CHOP CHOP — In-app notification helpers.
 * Stored in localStorage for the MVP; swap to a Supabase table when the
 * notification feature graduates from mock to production.
 */

export type NotificationKind =
  | "wallet"
  | "ride"
  | "delivery"
  | "marche"
  | "system";

export interface AppNotification {
  id: string;
  kind: NotificationKind;
  title: string;
  body: string;
  createdAt: string; // ISO
  read: boolean;
}

const KEY = "chopchop:notifications";
const QUEUE_KEY = "chopchop:notifications:offline-queue";
const FLUSHED_KEY = "chopchop:notifications:flushed-keys";
const MAX_FLUSHED = 500;

function read(): AppNotification[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    return JSON.parse(raw) as AppNotification[];
  } catch {
    return [];
  }
}

function write(list: AppNotification[]) {
  localStorage.setItem(KEY, JSON.stringify(list));
  window.dispatchEvent(new CustomEvent("chopchop:notifications:update"));
}

export const notifications = {
  list(): AppNotification[] {
    return read().sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
  },
  unreadCount(): number {
    return read().filter((n) => !n.read).length;
  },
  push(n: Omit<AppNotification, "id" | "createdAt" | "read">) {
    const item: AppNotification = {
      ...n,
      id: crypto.randomUUID(),
      createdAt: new Date().toISOString(),
      read: false,
    };
    write([item, ...read()].slice(0, 200));
    return item;
  },
  /**
   * Queue an in-app notification safely:
   *  - If online: push immediately.
   *  - If offline: persist to a local queue and flush on reconnect.
   * Dedup is per `dedupKey` (default = title+body) so re-mounts and
   * double-flushes never produce duplicate rows.
   */
  pushSafe(
    n: Omit<AppNotification, "id" | "createdAt" | "read">,
    dedupKey?: string,
  ) {
    const key = dedupKey ?? `${n.kind}|${n.title}|${n.body}`;
    if (hasFlushed(key)) return null;

    if (typeof navigator !== "undefined" && navigator.onLine === false) {
      enqueueOffline({ ...n, dedupKey: key });
      return null;
    }
    markFlushed(key);
    return notifications.push(n);
  },
  markAllRead() {
    write(read().map((n) => ({ ...n, read: true })));
  },
  markRead(id: string) {
    write(read().map((n) => (n.id === id ? { ...n, read: true } : n)));
  },
  clear() {
    write([]);
  },
  /** Flush the offline queue. Returns the number of newly-pushed rows. */
  flushOfflineQueue(): number {
    const queued = readQueue();
    if (queued.length === 0) return 0;
    let pushed = 0;
    const remaining: QueuedNotification[] = [];
    for (const q of queued) {
      if (hasFlushed(q.dedupKey)) continue;
      markFlushed(q.dedupKey);
      notifications.push({ kind: q.kind, title: q.title, body: q.body });
      pushed++;
    }
    writeQueue(remaining);
    return pushed;
  },
};

// ---------- Offline queue internals ----------

type QueuedNotification = Omit<AppNotification, "id" | "createdAt" | "read"> & {
  dedupKey: string;
};

function readQueue(): QueuedNotification[] {
  try {
    const raw = localStorage.getItem(QUEUE_KEY);
    return raw ? (JSON.parse(raw) as QueuedNotification[]) : [];
  } catch {
    return [];
  }
}

function writeQueue(list: QueuedNotification[]) {
  try { localStorage.setItem(QUEUE_KEY, JSON.stringify(list)); } catch {}
}

function enqueueOffline(item: QueuedNotification) {
  const list = readQueue();
  if (list.some((q) => q.dedupKey === item.dedupKey)) return;
  list.push(item);
  writeQueue(list);
}

function readFlushed(): Set<string> {
  try {
    const raw = localStorage.getItem(FLUSHED_KEY);
    return new Set(raw ? (JSON.parse(raw) as string[]) : []);
  } catch { return new Set(); }
}

function hasFlushed(key: string): boolean {
  return readFlushed().has(key);
}

function markFlushed(key: string) {
  try {
    const set = readFlushed();
    set.add(key);
    const arr = Array.from(set).slice(-MAX_FLUSHED);
    localStorage.setItem(FLUSHED_KEY, JSON.stringify(arr));
  } catch {}
}

// Auto-flush when the browser regains connectivity. Guarded so multiple
// imports / hot reloads don't register duplicate listeners.
if (typeof window !== "undefined" && !(window as any).__chopchopNotifFlushBound) {
  (window as any).__chopchopNotifFlushBound = true;
  let flushing = false;
  const flush = () => {
    if (flushing) return;
    flushing = true;
    try { notifications.flushOfflineQueue(); } finally { flushing = false; }
  };
  window.addEventListener("online", flush);
  // Also flush on load in case we came back online before this module mounted.
  if (navigator.onLine) setTimeout(flush, 0);
}
