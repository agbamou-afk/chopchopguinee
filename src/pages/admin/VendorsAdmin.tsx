import { useEffect, useState } from "react";
import { Loader2, Plus, Store, Wallet } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter } from "@/components/ui/dialog";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/format";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";

interface AgentRow {
  id: string; user_id: string; business_name: string; location: string | null;
  status: string; daily_limit_gnf: number; commission_rate: number; prepaid_float_gnf: number;
  profile?: { full_name: string | null; phone: string | null } | null;
}

export default function VendorsAdmin() {
  const { can } = useAdminAuth();
  const [agents, setAgents] = useState<AgentRow[]>([]);
  const [loading, setLoading] = useState(true);
  const load = async () => {
    setLoading(true);
    const { data: ags } = await supabase.from("agent_profiles").select("*").order("created_at", { ascending: false });
    const list = (ags ?? []) as AgentRow[];
    if (list.length) {
      const ids = list.map((a) => a.user_id);
      const { data: profs } = await supabase.from("profiles").select("user_id, full_name, phone").in("user_id", ids);
      const map = new Map((profs ?? []).map((p: any) => [p.user_id, p]));
      list.forEach((a) => { a.profile = map.get(a.user_id) as any; });
    }
    setAgents(list); setLoading(false);
  };
  useEffect(() => { load(); }, []);

  return (
    <ModulePage
      module="vendors"
      title="Agents de recharge"
      subtitle="Points cash-in, float prépayé et reconciliation"
      actions={can("vendors", "edit") && <CreateAgentDialog onCreated={load} />}
    >
      {loading ? (
        <div className="py-8 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-primary" /></div>
      ) : agents.length === 0 ? (
        <Card className="p-8 text-center text-sm text-muted-foreground">Aucun agent enregistré.</Card>
      ) : (
        <div className="space-y-3">
          {agents.map((a) => <AgentCard key={a.id} agent={a} canEdit={can("vendors", "edit")} onChanged={load} />)}
        </div>
      )}
    </ModulePage>
  );
}

function CreateAgentDialog({ onCreated }: { onCreated: () => void }) {
  const [open, setOpen] = useState(false);
  const [phone, setPhone] = useState(""); const [business, setBusiness] = useState("");
  const [location, setLocation] = useState(""); const [dailyLimit, setDailyLimit] = useState("5000000");
  const [commission, setCommission] = useState("0.01"); const [busy, setBusy] = useState(false);
  const create = async () => {
    setBusy(true);
    const { error } = await (supabase.rpc as any)("admin_create_agent", {
      p_phone: phone.trim(), p_business_name: business.trim(), p_location: location.trim() || null,
      p_daily_limit_gnf: Number(dailyLimit) || 0, p_commission_rate: Number(commission) || 0,
    });
    setBusy(false);
    if (error) { toast({ title: "Erreur", description: error.message }); return; }
    toast({ title: "Agent créé" }); setOpen(false); setPhone(""); setBusiness(""); setLocation(""); onCreated();
  };
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button size="sm" className="gradient-primary"><Plus className="w-4 h-4 mr-1" /> Agent</Button></DialogTrigger>
      <DialogContent>
        <DialogHeader><DialogTitle>Onboarder un agent</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label className="text-xs">Téléphone</Label><Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+224..." /></div>
          <div><Label className="text-xs">Nom du commerce</Label><Input value={business} onChange={(e) => setBusiness(e.target.value)} /></div>
          <div><Label className="text-xs">Quartier / Ville</Label><Input value={location} onChange={(e) => setLocation(e.target.value)} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label className="text-xs">Limite quotidienne</Label><Input type="number" value={dailyLimit} onChange={(e) => setDailyLimit(e.target.value)} /></div>
            <div><Label className="text-xs">Commission</Label><Input type="number" step="0.001" value={commission} onChange={(e) => setCommission(e.target.value)} /></div>
          </div>
        </div>
        <DialogFooter>
          <Button onClick={create} disabled={busy || !phone || !business} className="gradient-primary w-full">
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AgentCard({ agent, canEdit, onChanged }: { agent: AgentRow; canEdit: boolean; onChanged: () => void }) {
  const [open, setOpen] = useState(false);
  const [delta, setDelta] = useState(""); const [reason, setReason] = useState(""); const [busy, setBusy] = useState(false);
  const adjust = async (sign: 1 | -1) => {
    const amount = Number(delta);
    if (!amount) { toast({ title: "Montant invalide" }); return; }
    setBusy(true);
    const { error } = await (supabase.rpc as any)("admin_adjust_agent_float", {
      p_agent_user_id: agent.user_id, p_delta_gnf: sign * amount, p_reason: reason || null,
    });
    setBusy(false);
    if (error) { toast({ title: "Erreur", description: error.message }); return; }
    toast({ title: sign > 0 ? "Float crédité" : "Float débité" });
    setOpen(false); setDelta(""); setReason(""); onChanged();
  };
  return (
    <Card className="p-4">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center shrink-0">
            <Store className="w-5 h-5 text-primary-foreground" />
          </div>
          <div className="min-w-0">
            <h3 className="font-semibold truncate">{agent.business_name}</h3>
            <p className="text-xs text-muted-foreground truncate">
              {agent.profile?.full_name ?? "—"} · {agent.profile?.phone ?? agent.user_id.slice(0, 8)}
            </p>
          </div>
        </div>
        <div className="text-right shrink-0">
          <p className="text-xs text-muted-foreground">Float</p>
          <p className="font-semibold">{formatGNF(agent.prepaid_float_gnf)}</p>
        </div>
      </div>
      <div className="flex items-center gap-2 mt-3 flex-wrap">
        <span className="text-xs px-2 py-0.5 rounded-full bg-muted">{agent.status}</span>
        <span className="text-xs text-muted-foreground">Limite: {formatGNF(agent.daily_limit_gnf)}/j</span>
        <span className="text-xs text-muted-foreground">· {(agent.commission_rate * 100).toFixed(2)}%</span>
        {canEdit && (
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild><Button size="sm" variant="outline" className="ml-auto"><Wallet className="w-4 h-4 mr-1" />Float</Button></DialogTrigger>
            <DialogContent>
              <DialogHeader><DialogTitle>Ajuster le float</DialogTitle></DialogHeader>
              <div className="space-y-3">
                <div><Label className="text-xs">Montant</Label><Input type="number" value={delta} onChange={(e) => setDelta(e.target.value)} /></div>
                <div><Label className="text-xs">Motif</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} /></div>
              </div>
              <DialogFooter className="grid grid-cols-2 gap-2">
                <Button variant="outline" disabled={busy} onClick={() => adjust(-1)}>Débiter</Button>
                <Button className="gradient-primary" disabled={busy} onClick={() => adjust(1)}>
                  {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créditer"}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        )}
      </div>
    </Card>
  );
}