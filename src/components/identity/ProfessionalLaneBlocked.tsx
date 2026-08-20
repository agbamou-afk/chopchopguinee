import { useNavigate } from "react-router-dom";
import { ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { laneConflictMessage } from "@/hooks/useProfessionalLane";
import type { ProfessionalType } from "@/lib/identity/professionalIdentity";

/**
 * Honest refusal surface when a customer already holds the opposite
 * professional class. The server is the authority — this only avoids making
 * the user fill a form that can never succeed.
 */
export function ProfessionalLaneBlocked({
  lane,
  title,
}: {
  lane: ProfessionalType;
  title: string;
}) {
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-4">
      <div className="max-w-md w-full bg-card border border-border/60 rounded-3xl shadow-card p-6 text-center">
        <div className="w-12 h-12 rounded-2xl bg-destructive/10 flex items-center justify-center mx-auto mb-4">
          <ShieldAlert className="w-6 h-6 text-destructive" />
        </div>
        <h1 className="text-lg font-bold text-foreground mb-2">{title}</h1>
        <p className="text-sm text-muted-foreground mb-5">{laneConflictMessage(lane)}</p>
        <div className="flex flex-col gap-2">
          <Button onClick={() => navigate("/")}>Retour à l'accueil</Button>
          <Button variant="outline" onClick={() => navigate("/help")}>
            Contacter le support
          </Button>
        </div>
      </div>
    </div>
  );
}
