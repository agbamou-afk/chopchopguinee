import { useEffect, useRef, useState } from "react";
import { Html5Qrcode } from "html5-qrcode";
import { motion } from "framer-motion";
import { X, Camera, AlertCircle, Type } from "lucide-react";
import { Button } from "@/components/ui/button";

interface QrScannerProps {
  onResult: (text: string) => void;
  onClose: () => void;
  title?: string;
  subtitle?: string;
  expectedHint?: string;
}

export function QrScanner({ onResult, onClose, title = "Scanner un QR", subtitle, expectedHint }: QrScannerProps) {
  const containerId = "qr-reader-region";
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const startedRef = useRef(false);
  const stoppingRef = useRef(false);
  const [error, setError] = useState<string | null>(null);
  const [manual, setManual] = useState(false);
  const [manualVal, setManualVal] = useState("");
  const [starting, setStarting] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const stopSafely = async (s: Html5Qrcode | null) => {
      if (!s || stoppingRef.current) return;
      stoppingRef.current = true;
      try {
        // @ts-ignore
        const state = typeof s.getState === "function" ? s.getState() : 0;
        if (state === 2 || state === 3) {
          await s.stop();
        }
      } catch {}
      try { s.clear(); } catch {}
      stoppingRef.current = false;
    };
    const start = async () => {
      try {
        const html5 = new Html5Qrcode(containerId, { verbose: false });
        scannerRef.current = html5;
        await html5.start(
          { facingMode: "environment" },
          { fps: 10, qrbox: { width: 240, height: 240 } },
          (decoded) => {
            if (cancelled) return;
            handleResult(decoded);
          },
          () => {},
        );
        startedRef.current = true;
        if (cancelled) {
          // Unmounted while starting — stop now
          await stopSafely(html5);
          return;
        }
        setStarting(false);
      } catch (e: any) {
        setError(
          e?.message?.includes("Permission") || e?.name === "NotAllowedError"
            ? "Permission caméra refusée. Activez l'accès dans les réglages du navigateur."
            : "Impossible de démarrer la caméra.",
        );
        setStarting(false);
      }
    };
    start();
    return () => {
      cancelled = true;
      // Defer cleanup so an in-flight start() can finish first
      const s = scannerRef.current;
      setTimeout(() => { void stopSafely(s); }, 0);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleResult = async (text: string) => {
    const s = scannerRef.current;
    if (s && !stoppingRef.current) {
      stoppingRef.current = true;
      try {
        // @ts-ignore
        const state = typeof s.getState === "function" ? s.getState() : 0;
        if (state === 2 || state === 3) await s.stop();
      } catch {}
      stoppingRef.current = false;
    }
    onResult(text);
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-[60] bg-background flex flex-col"
    >
      <div className="gradient-primary px-4 py-3 flex items-center justify-between">
        <button
          onClick={onClose}
          className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition"
          aria-label="Fermer"
        >
          <X className="w-5 h-5 text-primary-foreground" />
        </button>
        <div className="text-primary-foreground text-sm font-semibold">{title}</div>
        <div className="w-9" />
      </div>

      <div className="flex-1 relative bg-black">
        <div id={containerId} className="absolute inset-0 [&_video]:!w-full [&_video]:!h-full [&_video]:object-cover" />

        {/* Overlay */}
        {!error && (
          <>
            <div className="absolute inset-0 pointer-events-none flex items-center justify-center">
              <div className="relative w-64 h-64 rounded-2xl border-2 border-primary shadow-[0_0_0_9999px_rgba(0,0,0,0.55)]">
                <motion.div
                  initial={{ y: 0 }}
                  animate={{ y: [0, 240, 0] }}
                  transition={{ duration: 2.4, repeat: Infinity, ease: "easeInOut" }}
                  className="absolute left-2 right-2 h-0.5 bg-primary shadow-[0_0_8px_hsl(var(--primary))]"
                />
              </div>
            </div>
            {starting && (
              <div className="absolute inset-0 flex items-center justify-center text-primary-foreground/90 text-sm">
                <Camera className="w-5 h-5 mr-2" /> Démarrage de la caméra…
              </div>
            )}
            {subtitle && (
              <div className="absolute top-3 left-1/2 -translate-x-1/2 bg-card/95 backdrop-blur shadow-elevated rounded-full px-4 py-1.5 text-xs font-semibold text-foreground">
                {subtitle}
              </div>
            )}
          </>
        )}

        {error && (
          <div className="absolute inset-0 flex flex-col items-center justify-center px-6 text-center text-primary-foreground">
            <AlertCircle className="w-10 h-10 text-destructive mb-3" />
            <p className="font-semibold mb-1">Caméra indisponible</p>
            <p className="text-sm text-primary-foreground/70">{error}</p>
          </div>
        )}
      </div>

      <div className="bg-card p-4 space-y-3">
        {!manual ? (
          <Button variant="outline" className="w-full h-11" onClick={() => setManual(true)}>
            <Type className="w-4 h-4 mr-2" /> Saisir le code manuellement
          </Button>
        ) : (
          <div className="space-y-2">
            <input
              autoFocus
              value={manualVal}
              onChange={(e) => setManualVal(e.target.value)}
              placeholder={expectedHint ?? "Entrer le code"}
              className="w-full bg-muted rounded-xl px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none"
            />
            <Button
              className="w-full h-11 gradient-primary"
              disabled={!manualVal.trim()}
              onClick={() => handleResult(manualVal.trim())}
            >
              Valider le code
            </Button>
          </div>
        )}
      </div>
    </motion.div>
  );
}
