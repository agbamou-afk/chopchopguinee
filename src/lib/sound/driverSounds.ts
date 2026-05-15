/**
 * Lightweight WebAudio-based operational cues for driver mode.
 * No external assets — synthesised soft sine tones, very low volume.
 * Respects a global mute flag (localStorage) and never autoplays before
 * a user interaction (browsers will otherwise block AudioContext).
 */

const MUTE_KEY = "chop:driver:soundsMuted";

let ctx: AudioContext | null = null;
let unlocked = false;

function getCtx(): AudioContext | null {
  if (typeof window === "undefined") return null;
  try {
    if (!ctx) {
      const Ctor = (window.AudioContext || (window as any).webkitAudioContext) as
        | typeof AudioContext
        | undefined;
      if (!Ctor) return null;
      ctx = new Ctor();
    }
    return ctx;
  } catch {
    return null;
  }
}

/** Call inside any user gesture handler to unlock audio. */
export function unlockDriverSounds() {
  const c = getCtx();
  if (!c) return;
  if (c.state === "suspended") c.resume().catch(() => {});
  unlocked = true;
}

export function isDriverSoundsMuted(): boolean {
  try {
    return localStorage.getItem(MUTE_KEY) === "1";
  } catch {
    return false;
  }
}

export function setDriverSoundsMuted(muted: boolean) {
  try {
    localStorage.setItem(MUTE_KEY, muted ? "1" : "0");
  } catch {
    /* noop */
  }
}

interface ToneStep {
  freq: number;
  /** seconds */
  start: number;
  /** seconds */
  duration: number;
  /** 0..1, applied on top of the global soft volume */
  gain?: number;
}

function playTones(steps: ToneStep[]) {
  if (isDriverSoundsMuted()) return;
  const c = getCtx();
  if (!c || !unlocked) return;
  const master = c.createGain();
  master.gain.value = 0.06; // global "calming" cap
  master.connect(c.destination);
  const now = c.currentTime;
  for (const s of steps) {
    const osc = c.createOscillator();
    const g = c.createGain();
    osc.type = "sine";
    osc.frequency.value = s.freq;
    const peak = s.gain ?? 0.9;
    g.gain.setValueAtTime(0.0001, now + s.start);
    g.gain.exponentialRampToValueAtTime(peak, now + s.start + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, now + s.start + s.duration);
    osc.connect(g).connect(master);
    osc.start(now + s.start);
    osc.stop(now + s.start + s.duration + 0.02);
  }
}

/** Soft two-note ascending chime (incoming offer). */
export function playOfferIncoming() {
  playTones([
    { freq: 660, start: 0, duration: 0.18 },
    { freq: 880, start: 0.16, duration: 0.22 },
  ]);
}

/** Confirming low-key blip (accept). */
export function playOfferAccepted() {
  playTones([{ freq: 520, start: 0, duration: 0.12 }, { freq: 780, start: 0.1, duration: 0.18 }]);
}

/** Soft single tone (arrived at pickup). */
export function playArrivedAtPickup() {
  playTones([{ freq: 740, start: 0, duration: 0.25 }]);
}

/** Calm closing chord (ride completed). */
export function playRideCompleted() {
  playTones([
    { freq: 523, start: 0, duration: 0.3 },
    { freq: 659, start: 0.05, duration: 0.32 },
    { freq: 784, start: 0.1, duration: 0.36 },
  ]);
}