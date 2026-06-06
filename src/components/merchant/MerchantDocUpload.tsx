import { useRef, useState } from "react";
import { Camera, Loader2, Check, IdCard, User, Store as StoreIcon } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";

export type DocKind = "id-card" | "selfie" | "storefront";

const META: Record<DocKind, { label: string; help: string; icon: typeof IdCard; required: boolean }> = {
  "id-card": { label: "Pièce d'identité", help: "Carte d'identité ou passeport, visible et lisible.", icon: IdCard, required: true },
  selfie: { label: "Selfie de vérification", help: "Photo de vous tenant votre pièce d'identité.", icon: User, required: true },
  storefront: { label: "Photo de la boutique (optionnel)", help: "Photo de l'entrée ou de l'étal.", icon: StoreIcon, required: false },
};

type Props = {
  kind: DocKind;
  currentPath: string | null;
  onUploaded: (path: string) => void;
};

export function MerchantDocUpload({ kind, currentPath, onUploaded }: Props) {
  const { user } = useAuth();
  const inputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const M = META[kind];
  const Icon = M.icon;

  const pick = () => inputRef.current?.click();

  const onFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (file.size > 8 * 1024 * 1024) {
      toast({ title: "Fichier trop volumineux", description: "Maximum 8 Mo." });
      return;
    }
    setBusy(true);
    const ext = (file.name.split(".").pop() || "jpg").toLowerCase();
    const path = `${user.id}/${kind}-${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from("merchant-docs").upload(path, file, {
      upsert: true,
      contentType: file.type || undefined,
    });
    setBusy(false);
    if (error) {
      toast({ title: "Erreur d'envoi", description: error.message });
      return;
    }
    onUploaded(path);
    toast({ title: "Document enregistré", description: M.label });
  };

  return (
    <div className="flex items-start gap-3 rounded-2xl border border-border/60 p-3 bg-card">
      <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
        <Icon className="w-5 h-5 text-primary" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-foreground">
          {M.label} {M.required && <span className="text-destructive">*</span>}
        </p>
        <p className="text-[11px] text-muted-foreground leading-snug">{M.help}</p>
        {currentPath && (
          <p className="text-[11px] text-primary mt-1 flex items-center gap-1">
            <Check className="w-3 h-3" /> Document enregistré
          </p>
        )}
      </div>
      <Button type="button" size="sm" variant="outline" onClick={pick} disabled={busy} className="flex-shrink-0">
        {busy ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Camera className="w-3.5 h-3.5" />}
        <span className="ml-1 text-xs">{currentPath ? "Remplacer" : "Envoyer"}</span>
      </Button>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        capture={kind === "selfie" ? "user" : "environment"}
        onChange={onFile}
        className="hidden"
      />
    </div>
  );
}
