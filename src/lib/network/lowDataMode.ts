/**
 * Low-data / save-data detection for Conakry's spotty mobile networks.
 *
 * Combines the Network Information API (`saveData`, `effectiveType`) with a
 * user-overridable preference stored in localStorage. UI surfaces (maps,
 * marker animations, image loaders) should consult `isLowDataMode()` to
 * cut bandwidth and CPU when appropriate.
 */
const KEY = 'cc_low_data_pref';
type Pref = 'auto' | 'on' | 'off';

function getConn(): any {
  return (typeof navigator !== 'undefined' && (navigator as any).connection) || null;
}

export function networkSignals() {
  const c = getConn();
  return {
    saveData: !!c?.saveData,
    effectiveType: (c?.effectiveType as string | undefined) ?? null,
    downlink: (c?.downlink as number | undefined) ?? null,
  };
}

export function getLowDataPref(): Pref {
  if (typeof window === 'undefined') return 'auto';
  const v = localStorage.getItem(KEY);
  return v === 'on' || v === 'off' ? v : 'auto';
}

export function setLowDataPref(p: Pref) {
  try { localStorage.setItem(KEY, p); window.dispatchEvent(new Event('cc:lowdata')); } catch {}
}

export function isLowDataMode(): boolean {
  const pref = getLowDataPref();
  if (pref === 'on') return true;
  if (pref === 'off') return false;
  const s = networkSignals();
  if (s.saveData) return true;
  if (s.effectiveType === '2g' || s.effectiveType === 'slow-2g') return true;
  if (typeof s.downlink === 'number' && s.downlink > 0 && s.downlink < 0.7) return true;
  return false;
}

export function subscribeLowData(cb: () => void): () => void {
  if (typeof window === 'undefined') return () => {};
  const handler = () => cb();
  window.addEventListener('cc:lowdata', handler);
  const c = getConn();
  c?.addEventListener?.('change', handler);
  return () => {
    window.removeEventListener('cc:lowdata', handler);
    c?.removeEventListener?.('change', handler);
  };
}