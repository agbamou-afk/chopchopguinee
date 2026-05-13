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
  markAllRead() {
    write(read().map((n) => ({ ...n, read: true })));
  },
  markRead(id: string) {
    write(read().map((n) => (n.id === id ? { ...n, read: true } : n)));
  },
  clear() {
    write([]);
  },
};
