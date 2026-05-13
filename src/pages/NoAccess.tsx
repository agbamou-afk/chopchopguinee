import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { ShieldAlert } from "lucide-react";

export default function NoAccess() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center bg-background px-6 text-center">
      <ShieldAlert className="w-12 h-12 text-destructive mb-4" />
      <h1 className="text-2xl font-bold mb-2">Accès refusé</h1>
      <p className="text-sm text-muted-foreground max-w-sm mb-6">
        Votre compte n'a pas les permissions nécessaires pour accéder à cette section.
      </p>
      <Button asChild className="gradient-primary">
        <Link to="/">Retour à l'application</Link>
      </Button>
    </div>
  );
}