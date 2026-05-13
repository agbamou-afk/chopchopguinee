import { useEffect, useState } from "react";
import { Loader2, Plus, UserCog } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogFooter } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ModulePage } from "@/components/admin/ModulePage";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { ROLE_LABELS, AdminRole } from "@/lib/admin/permissions";
import { logAction } from "@/lib/admin/approvals";
import { toast } from "@/hooks/use-toast";

interface AdminUserRow {
  id: string; user_id: string; admin_role: AdminRole; status: string; notes: string | null; created_at: string;
  profile?: { full_name: string | null; phone: string | null } | null;
}

export default function AdminsAdmin() {
  const { isSuperAdmin } = useAdminAuth();
  const [tab, setTab] = useState("admins");
  return (
    <ModulePage module="admins" title="Administrateurs" subtitle="Gestion des comptes admin et file d'approbations">
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="admins">Comptes admin</TabsTrigger>
          <TabsTrigger value="approvals">File d'approbations</TabsTrigger>
        </TabsList>
        <TabsContent value="admins" className="mt-4"><AdminsList canManage={isSuperAdmin} /></TabsContent>
        <TabsContent value="approvals" className="mt-4"><ApprovalsList canReview={isSuperAdmin} /></TabsContent>
      </Tabs>
    </ModulePage>
  );
}

function AdminsList({ canManage }: { canManage: boolean }) {
  const [rows, setRows] = useState<AdminUserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const load = async () => {
    setLoading(true);
    const { data } = await supabase.from("admin_users").select("*").order("created_at", { ascending: false });
    const list = (data ?? []) as AdminUserRow[];
    if (list.length) {
      const ids = list.map((r) => r.user_id);
      const { data: profs } = await supabase.from("profiles").select("user_id, full_name, phone").in("user_id", ids);
      const map = new Map((profs ?? []).map((p: any) => [p.user_id, p]));
      list.forEach((r) => { r.profile = map.get(r.user_id) as any; });
    }
    setRows(list); setLoading(false);
  };
  useEffect(() => { load(); }, []);

  return (
    <div className="space-y-3">
      {canManage && <CreateAdminDialog onCreated={load} />}
      {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : rows.map((r) => (
        <Card key={r.id} className="p-4 flex items-center justify-between gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-10 h-10 rounded-xl bg-muted flex items-center justify-center"><UserCog className="w-5 h-5" /></div>
            <div className="min-w-0">
              <p className="font-semibold">{r.profile?.full_name ?? r.profile?.phone ?? r.user_id.slice(0, 8)}</p>
              <p className="text-xs text-muted-foreground">{r.profile?.phone ?? "—"}</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge>{ROLE_LABELS[r.admin_role]}</Badge>
            <Badge variant={r.status === "active" ? "secondary" : "destructive"}>{r.status}</Badge>
          </div>
        </Card>
      ))}
    </div>
  );
}

function CreateAdminDialog({ onCreated }: { onCreated: () => void }) {
  const [open, setOpen] = useState(false);
  const [phone, setPhone] = useState(""); const [role, setRole] = useState<AdminRole>("ops_admin");
  const [notes, setNotes] = useState(""); const [busy, setBusy] = useState(false);
  const create = async () => {
    setBusy(true);
    const { data: profile, error: pErr } = await supabase.from("profiles").select("user_id").eq("phone", phone.trim()).maybeSingle();
    if (pErr || !profile) { toast({ title: "Utilisateur introuvable" }); setBusy(false); return; }
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from("admin_users").insert({
      user_id: profile.user_id, admin_role: role, notes: notes || null, created_by: user?.id ?? null,
    });
    if (error) { toast({ title: "Erreur", description: error.message }); setBusy(false); return; }
    await logAction({ module: "admins", action: "admin.create", target_type: "user", target_id: profile.user_id, after: { admin_role: role } });
    toast({ title: "Admin créé" }); setOpen(false); setPhone(""); setNotes(""); setBusy(false); onCreated();
  };
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild><Button className="gradient-primary"><Plus className="w-4 h-4 mr-1" />Nouvel admin</Button></DialogTrigger>
      <DialogContent>
        <DialogHeader><DialogTitle>Créer un administrateur</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label className="text-xs">Téléphone du compte</Label><Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+224..." /></div>
          <div>
            <Label className="text-xs">Rôle</Label>
            <Select value={role} onValueChange={(v) => setRole(v as AdminRole)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="super_admin">Super Admin</SelectItem>
                <SelectItem value="ops_admin">Operations Admin</SelectItem>
                <SelectItem value="finance_admin">Finance Admin</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div><Label className="text-xs">Notes</Label><Input value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button onClick={create} disabled={busy || !phone} className="gradient-primary w-full">
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Créer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ApprovalsList({ canReview }: { canReview: boolean }) {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const load = async () => {
    setLoading(true);
    const { data } = await supabase.from("approval_requests").select("*").order("created_at", { ascending: false }).limit(100);
    setRows(data ?? []); setLoading(false);
  };
  useEffect(() => { load(); }, []);
  const review = async (id: string, status: "approved" | "rejected") => {
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from("approval_requests").update({
      status, reviewed_by: user?.id ?? null, reviewed_at: new Date().toISOString(),
    }).eq("id", id);
    if (error) { toast({ title: "Erreur", description: error.message }); return; }
    await logAction({ module: "admins", action: `approval.${status}`, target_type: "approval_request", target_id: id });
    load();
  };
  if (loading) return <Loader2 className="w-5 h-5 animate-spin" />;
  if (!rows.length) return <Card className="p-8 text-center text-sm text-muted-foreground">Aucune demande d'approbation.</Card>;
  return (
    <div className="space-y-3">
      {rows.map((r) => (
        <Card key={r.id} className="p-4">
          <div className="flex items-center justify-between gap-2">
            <div>
              <p className="font-semibold">{r.action}</p>
              <p className="text-xs text-muted-foreground">{r.module} · {new Date(r.created_at).toLocaleString()}</p>
            </div>
            <Badge variant={r.status === "pending" ? "secondary" : r.status === "approved" ? "default" : "destructive"}>{r.status}</Badge>
          </div>
          {Object.keys(r.payload ?? {}).length > 0 && (
            <pre className="mt-2 p-2 bg-muted rounded text-xs overflow-x-auto">{JSON.stringify(r.payload, null, 2)}</pre>
          )}
          {canReview && r.status === "pending" && (
            <div className="flex gap-2 mt-3">
              <Button size="sm" onClick={() => review(r.id, "approved")} className="gradient-primary">Approuver</Button>
              <Button size="sm" variant="outline" onClick={() => review(r.id, "rejected")}>Rejeter</Button>
            </div>
          )}
        </Card>
      ))}
    </div>
  );
}