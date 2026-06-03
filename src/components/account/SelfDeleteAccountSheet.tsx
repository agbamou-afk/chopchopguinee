import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { AlertTriangle, Loader2 } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { toast } from "@/hooks/use-toast";

const CONFIRM_TOKEN = "SUPPRIMER";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * Real self-delete sheet. Calls request_account_deletion() which anonymizes
 * the profile, suspends any driver record, and archives merchant/listing
 * surfaces. Wallet and audit history are preserved by design. After success
 * the user is signed out and sent to /auth.
 */
export function SelfDeleteAccountSheet({ open, onOpenChange }: Props) {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();
  const [confirm, setConfirm] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  const close = () => {
    onOpenChange(false);
    setTimeout(() => {
      setConfirm("");
      setReason("");
    }, 250);
  };

  const submit = async () => {
    if (!user) return;
    if (confirm.trim().toUpperCase() !== CONFIRM_TOKEN) {
      toast({ title: "Confirmation requise", description: `Tapez ${CONFIRM_TOKEN} pour confirmer.` });
      return;
    }
    setBusy(true);
    const { error } = await supabase.rpc("request_account_deletion", {
      _reason: reason.trim() || null,
    });
    setBusy(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    toast({ title: "Votre compte a été supprimé." });
    await signOut();
    navigate("/auth", { replace: true });
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="bottom"
        className="max-w-md mx-auto rounded-t-3xl max-h-[85vh] overflow-y-auto"
      >
        <SheetHeader className="text-left">
          <SheetTitle className="flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-destructive" />
            Confirmer la suppression du compte
          </SheetTitle>
          <SheetDescription className="text-[13px] leading-snug text-muted-foreground">
            Cette action est importante. Vous serez déconnecté et votre profil ne sera plus actif.
            Les données nécessaires à la sécurité, aux paiements et aux obligations légales peuvent
            être conservées.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 space-y-4">
          <div>
            <Label htmlFor="confirm-token" className="text-[12px] font-semibold">
              Pour confirmer, tapez {CONFIRM_TOKEN}
            </Label>
            <Input
              id="confirm-token"
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              placeholder={CONFIRM_TOKEN}
              autoComplete="off"
              className="mt-1"
            />
          </div>
          <div>
            <Label htmlFor="reason" className="text-[12px] font-semibold">
              Raison (facultatif)
            </Label>
            <Textarea
              id="reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              maxLength={500}
              className="mt-1"
            />
          </div>
        </div>

        <SheetFooter className="gap-2 sm:gap-2 mt-4">
          <Button variant="outline" onClick={close} disabled={busy}>
            Annuler
          </Button>
          <Button
            variant="destructive"
            onClick={submit}
            disabled={busy || confirm.trim().toUpperCase() !== CONFIRM_TOKEN}
            className="gap-2"
          >
            {busy && <Loader2 className="w-4 h-4 animate-spin" />}
            Confirmer la suppression
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}