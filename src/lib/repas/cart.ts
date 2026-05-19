import { useCallback, useEffect, useState } from "react";

export interface CartLine {
  menuItemId: string;
  name: string;
  unitPriceGnf: number;
  qty: number;
  photoUrl?: string | null;
}

export interface CartState {
  restaurantId: string | null;
  restaurantName: string | null;
  lines: CartLine[];
}

const STORAGE_KEY = "cc_repas_cart_v1";
const EVENT = "cc_repas_cart_changed";

function readStorage(): CartState {
  if (typeof window === "undefined") return { restaurantId: null, restaurantName: null, lines: [] };
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return { restaurantId: null, restaurantName: null, lines: [] };
    return JSON.parse(raw) as CartState;
  } catch {
    return { restaurantId: null, restaurantName: null, lines: [] };
  }
}

function writeStorage(s: CartState) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    window.dispatchEvent(new CustomEvent(EVENT));
  } catch {}
}

export function useRepasCart() {
  const [state, setState] = useState<CartState>(() => readStorage());

  useEffect(() => {
    const sync = () => setState(readStorage());
    window.addEventListener(EVENT, sync);
    window.addEventListener("storage", sync);
    return () => {
      window.removeEventListener(EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const setCart = useCallback((next: CartState) => {
    writeStorage(next);
    setState(next);
  }, []);

  const addItem = useCallback(
    (restaurantId: string, restaurantName: string, line: Omit<CartLine, "qty"> & { qty?: number }) => {
      const current = readStorage();
      // Single-restaurant cart — clear when switching restaurants
      const base: CartState =
        current.restaurantId && current.restaurantId !== restaurantId
          ? { restaurantId, restaurantName, lines: [] }
          : { restaurantId, restaurantName, lines: current.lines };
      const existing = base.lines.find((l) => l.menuItemId === line.menuItemId);
      if (existing) {
        existing.qty += line.qty ?? 1;
      } else {
        base.lines.push({ ...line, qty: line.qty ?? 1 });
      }
      writeStorage(base);
      setState(base);
    },
    [],
  );

  const updateQty = useCallback((menuItemId: string, qty: number) => {
    const current = readStorage();
    const lines = current.lines
      .map((l) => (l.menuItemId === menuItemId ? { ...l, qty } : l))
      .filter((l) => l.qty > 0);
    const next: CartState =
      lines.length === 0
        ? { restaurantId: null, restaurantName: null, lines: [] }
        : { ...current, lines };
    writeStorage(next);
    setState(next);
  }, []);

  const clear = useCallback(() => {
    const empty: CartState = { restaurantId: null, restaurantName: null, lines: [] };
    writeStorage(empty);
    setState(empty);
  }, []);

  const subtotal = state.lines.reduce((s, l) => s + l.unitPriceGnf * l.qty, 0);
  const itemCount = state.lines.reduce((s, l) => s + l.qty, 0);

  return { ...state, subtotal, itemCount, addItem, updateQty, clear, setCart };
}
