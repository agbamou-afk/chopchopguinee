import { useEffect, useState } from "react";
import { Shield, Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { formatGNF } from "@/lib/format";

/**
 * God-admin-only platform balance card. Calls a SECURITY DEFINER RPC that
 * self-guards on `is_god_admin`; non-god callers get `not_authorized` and the
 * component silently hides itself.
 */
export function MasterWalletCard() {
  const [balance, setBalance] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data, error } = await supabase.rpc("wallet_get_master_balance");
      if (!alive) return;
      if (error) {
        setVisible(false);
      } else {
        setVisible(true);
        setBalance(typeof data === "number" ? data : Number(data ?? 0));
      }
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  if (!loading && !visible) return null;

  return (
    <Card className="p-4 mb-4 bg-gradient-to-br from-primary/10 to-primary/5 border-primary/30">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Shield className="w-5 h-5 text-primary" />
          <div>
            <div className="text-xs uppercase tracking-wide text-muted-foreground">
              Master Wallet (God Admin)
            </div>
            <div className="text-2xl font-bold">
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : formatGNF(balance ?? 0)}
            </div>
          </div>
        </div>
        <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
          Revenus plateforme
        </span>
      </div>
    </Card>
  );
}