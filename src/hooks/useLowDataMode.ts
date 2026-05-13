import { useEffect, useState } from 'react';
import { isLowDataMode, subscribeLowData, getLowDataPref, setLowDataPref, networkSignals } from '@/lib/network/lowDataMode';

export function useLowDataMode() {
  const [low, setLow] = useState<boolean>(() => isLowDataMode());
  const [pref, setPref] = useState(() => getLowDataPref());
  useEffect(() => subscribeLowData(() => { setLow(isLowDataMode()); setPref(getLowDataPref()); }), []);
  return {
    low,
    pref,
    signals: networkSignals(),
    setPref: (p: 'auto' | 'on' | 'off') => setLowDataPref(p),
  };
}