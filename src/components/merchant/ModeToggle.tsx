import { useEffect, useState } from "react";
import { Store, ShoppingBag } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useAppMode, useSwitchAppMode } from "@/hooks/useAppMode";
import { Button } from "@/components/ui/button";

/** Toggle visible only to users that own a merchant_store. Switching does not delete
 * the store or change approval status; it just routes the user between the
 * merchant dashboard and the client home. */
export function MerchantModeToggle({ compact = false }: { compact?: boolean }) {
  const { user } = useAuth();
  const { mode } = useAppMode();
  const switchAppMode = useSwitchAppMode();
  const [hasStore, setHasStore] = useState(false);

  useEffect(() => {
    if (!user) return;
    (async () => {
      const [{ data: s }, { data: r }] = await Promise.all([
        (supabase as any)
          .from("merchant_stores")
          .select("id")
          .eq("owner_user_id", user.id)
          .maybeSingle(),
        (supabase as any)
          .from("food_restaurants")
          .select("id")
          .eq("owner_user_id", user.id)
          .maybeSingle(),
      ]);
      setHasStore(!!(s?.id || r?.id));
    })();
  }, [user]);

  if (!hasStore) return null;

  const switchTo = (next: "merchant" | "client") => switchAppMode(next);

  if (mode === "merchant") {
    return (
      <Button
        variant="outline"
        size={compact ? "sm" : "default"}
        onClick={() => switchTo("client")}
        className="gap-2"
      >
        <ShoppingBag className="w-4 h-4" />
        Passer en mode client
      </Button>
    );
  }
  return (
    <Button
      variant="outline"
      size={compact ? "sm" : "default"}
      onClick={() => switchTo("merchant")}
      className="gap-2"
    >
      <Store className="w-4 h-4" />
      Passer en mode marchand
    </Button>
  );
}
