import { useState } from "react";
import { motion } from "framer-motion";
import { ShieldCheck, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { hashPin } from "@/hooks/useWallet";
import {
  InputOTP,
  InputOTPGroup,
  InputOTPSlot,
} from "@/components/ui/input-otp";
import { Button } from "@/components/ui/button";

interface PinSetupProps {
  userId: string;
  onDone: () => void;
}

export function PinSetup({ userId, onDone }: PinSetupProps) {
  const [step, setStep] = useState<"create" | "confirm">("create");
  const [pin, setPin] = useState("");
  const [confirm, setConfirm] = useState("");
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    if (pin.length !== 6) {
      toast.error("Le code PIN doit contenir 6 chiffres");
      return;
    }
    if (pin !== confirm) {
      toast.error("Les deux codes ne correspondent pas");
      setConfirm("");
      setStep("confirm");
      return;
    }
    setSaving(true);
    try {
      const pin_hash = await hashPin(pin, userId);
      const { error } = await supabase
        .from("user_pins")
        .upsert(
          { user_id: userId, pin_hash },
          { onConflict: "user_id" },
        );
      if (error) throw error;
      toast.success("Code PIN enregistré");
      onDone();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Erreur inconnue";
      toast.error(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-card rounded-2xl p-5 shadow-card border"
    >
      <div className="flex items-center gap-3 mb-3">
        <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center">
          <ShieldCheck className="w-5 h-5 text-primary-foreground" />
        </div>
        <div>
          <p className="font-semibold text-foreground">Sécurisez votre portefeuille</p>
          <p className="text-xs text-muted-foreground">
            {step === "create"
              ? "Créez un code PIN à 6 chiffres"
              : "Confirmez votre code PIN"}
          </p>
        </div>
      </div>

      <div className="flex justify-center my-4">
        {step === "create" ? (
          <InputOTP maxLength={6} value={pin} onChange={setPin}>
            <InputOTPGroup>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <InputOTPSlot key={i} index={i} />
              ))}
            </InputOTPGroup>
          </InputOTP>
        ) : (
          <InputOTP maxLength={6} value={confirm} onChange={setConfirm}>
            <InputOTPGroup>
              {[0, 1, 2, 3, 4, 5].map((i) => (
                <InputOTPSlot key={i} index={i} />
              ))}
            </InputOTPGroup>
          </InputOTP>
        )}
      </div>

      {step === "create" ? (
        <Button
          onClick={() => {
            if (pin.length !== 6) {
              toast.error("6 chiffres requis");
              return;
            }
            setStep("confirm");
          }}
          className="w-full gradient-primary"
        >
          Continuer
        </Button>
      ) : (
        <div className="flex gap-2">
          <Button
            variant="outline"
            onClick={() => {
              setConfirm("");
              setStep("create");
            }}
            className="flex-1"
          >
            Retour
          </Button>
          <Button onClick={submit} disabled={saving} className="flex-1 gradient-primary">
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Activer"}
          </Button>
        </div>
      )}
    </motion.div>
  );
}