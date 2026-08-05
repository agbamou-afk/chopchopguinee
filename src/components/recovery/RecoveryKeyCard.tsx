import { useMemo, useState } from "react";
import { Copy, Check, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";

/**
 * Shows the CHOPCHOP recovery key exactly once and refuses to move on until
 * the user proves they wrote it down by re-typing its last 4 characters.
 *
 * The key lives in React state only. It is never written to storage, the URL,
 * analytics or the console, and the server can never redisplay it.
 */
export function RecoveryKeyCard({
  recoveryKey,
  busy,
  onConfirm,
  confirmLabel = "Terminer",
}: {
  recoveryKey: string;
  busy?: boolean;
  onConfirm: (tail: string) => void;
  confirmLabel?: string;
}) {
  const [tail, setTail] = useState("");
  const [copied, setCopied] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const groups = useMemo(() => recoveryKey.split("-"), [recoveryKey]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(recoveryKey);
      setCopied(true);
      setAcknowledged(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast({
        title: "Copie impossible",
        description: "Recopiez la clé à la main sur un papier sûr.",
      });
    }
  };

  const share = async () => {
    const nav = navigator as Navigator & { share?: (d: ShareData) => Promise<void> };
    if (!nav.share) {
      void copy();
      return;
    }
    try {
      await nav.share({
        title: "Clé de récupération CHOPCHOP",
        text: `Clé de récupération CHOPCHOP : ${recoveryKey}`,
      });
      setAcknowledged(true);
    } catch {
      /* user cancelled */
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-start gap-2 rounded-2xl bg-primary/5 border border-primary/20 p-3">
        <ShieldCheck className="w-5 h-5 text-primary shrink-0 mt-0.5" aria-hidden />
        <p className="text-[12px] text-muted-foreground leading-snug">
          Voici votre clé de récupération CHOPCHOP. Elle s'affiche{" "}
          <strong className="text-foreground">une seule fois</strong>. Sans elle, personne — pas
          même l'équipe CHOPCHOP — ne pourra réinitialiser votre mot de passe.
        </p>
      </div>

      <div
        className="rounded-2xl border border-border bg-muted/40 p-4 text-center"
        aria-label="Clé de récupération"
      >
        <div className="flex flex-wrap justify-center gap-x-2 gap-y-1 font-mono text-base font-semibold tracking-widest text-foreground">
          {groups.map((g, i) => (
            <span key={i}>{g}</span>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Button type="button" variant="outline" onClick={copy} className="h-11">
          {copied ? <Check className="w-4 h-4 mr-1" /> : <Copy className="w-4 h-4 mr-1" />}
          {copied ? "Copiée" : "Copier"}
        </Button>
        <Button type="button" variant="outline" onClick={share} className="h-11">
          Enregistrer
        </Button>
      </div>

      <div>
        <Label htmlFor="key-tail">Confirmez les 4 derniers caractères</Label>
        <Input
          id="key-tail"
          value={tail}
          onChange={(e) => setTail(e.target.value.toUpperCase().slice(0, 4))}
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          inputMode="text"
          maxLength={4}
          placeholder="XXXX"
          className="font-mono tracking-widest"
        />
        <p className="text-[11px] text-muted-foreground mt-1">
          Recopiez les 4 derniers caractères pour confirmer que vous l'avez bien enregistrée.
        </p>
      </div>

      <Button
        type="button"
        disabled={busy || tail.length !== 4}
        onClick={() => onConfirm(tail)}
        className="w-full h-12 gradient-primary"
      >
        {confirmLabel}
      </Button>
      {!acknowledged && (
        <p className="text-[11px] text-muted-foreground text-center" role="status">
          Copiez ou notez la clé avant de continuer.
        </p>
      )}
    </div>
  );
}