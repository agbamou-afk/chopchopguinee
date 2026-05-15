import { useState, useCallback } from "react";
import { QrScanner } from "@/components/scanner/QrScanner";
import { ChopPaySheet } from "./ChopPaySheet";
import { parseChopPayPayload, type ChopPayPayload } from "@/lib/choppay";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import { toast } from "sonner";

interface Props {
  open: boolean;
  onClose: () => void;
}

/**
 * Wires the QR scanner to the CHOPPay payment sheet:
 *  1. open=true → camera scanner mounts
 *  2. on decode → parse payload, open payment sheet
 *  3. on close (either) → onClose()
 */
export function ChopPayLauncher({ open, onClose }: Props) {
  const [payload, setPayload] = useState<ChopPayPayload | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);

  const onScan = useCallback((text: string) => {
    const parsed = parseChopPayPayload(text);
    if (!parsed) {
      Analytics.track("qr.scan_invalid", { metadata: { sample: text.slice(0, 32) } });
      try {
        toast.error("QR non reconnu", {
          description: "Ce code n'est pas un QR de paiement CHOPPay.",
        });
      } catch {}
      return;
    }
    setPayload(parsed);
    setSheetOpen(true);
  }, []);

  const closeAll = () => {
    setSheetOpen(false);
    setPayload(null);
    onClose();
  };

  return (
    <>
      {open && !sheetOpen && (
        <QrScanner
          title="Scanner pour payer"
          subtitle="CHOPPay · marchand"
          expectedHint="Code marchand CHOPPay"
          onResult={onScan}
          onClose={onClose}
        />
      )}
      <ChopPaySheet open={sheetOpen} payload={payload} onClose={closeAll} />
    </>
  );
}