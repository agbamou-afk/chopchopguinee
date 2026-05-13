import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, StatusBadge, AdminToolbar } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { MessageSquare, Send, CheckCircle2, XCircle } from "lucide-react";

const TEMPLATES = [
  { name: "OTP", channel: "whatsapp", body: "Votre code CHOP CHOP : {{code}}", status: "active" },
  { name: "Wallet top-up success", channel: "whatsapp", body: "Recharge confirmée : {{amount}} GNF", status: "active" },
  { name: "Ride confirmed", channel: "sms", body: "Course confirmée. Chauffeur arrive dans {{eta}}.", status: "active" },
  { name: "Refund issued", channel: "whatsapp", body: "Remboursement de {{amount}} GNF effectué.", status: "active" },
];

const RECENT = [
  { to: "+224 622...", template: "OTP", status: "completed", t: "il y a 1 min" },
  { to: "+224 620...", template: "Ride confirmed", status: "completed", t: "il y a 3 min" },
  { to: "+224 628...", template: "Wallet success", status: "failed", t: "il y a 12 min" },
];

export default function NotificationsAdmin() {
  return (
    <ModulePage module="notifications" title="Notifications" subtitle="WhatsApp, SMS, push et campagnes">
      <StatGrid items={[
        { label: "Envoyés 24h", value: "12 480", icon: Send, tone: "text-primary" },
        { label: "Délivrés", value: "98.2%", icon: CheckCircle2, tone: "text-emerald-600" },
        { label: "Échecs", value: "224", icon: XCircle, tone: "text-rose-600" },
        { label: "Templates actifs", value: "18", icon: MessageSquare, tone: "text-amber-600" },
      ]} />
      <Tabs defaultValue="templates">
        <TabsList>
          <TabsTrigger value="templates">Templates</TabsTrigger>
          <TabsTrigger value="broadcast">Diffusion</TabsTrigger>
          <TabsTrigger value="log">Journal</TabsTrigger>
        </TabsList>
        <TabsContent value="templates" className="mt-4 space-y-2">
          {TEMPLATES.map((t) => (
            <Card key={t.name} className="p-4 flex items-center gap-3">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="font-semibold text-sm">{t.name}</p>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-muted">{t.channel}</span>
                  <StatusBadge status={t.status} />
                </div>
                <p className="text-xs text-muted-foreground truncate mt-0.5">{t.body}</p>
              </div>
              <Button size="sm" variant="ghost">Éditer</Button>
            </Card>
          ))}
        </TabsContent>
        <TabsContent value="broadcast" className="mt-4">
          <Card className="p-5 space-y-3">
            <p className="text-sm font-semibold">Composer une annonce</p>
            <Textarea rows={4} placeholder="Message à diffuser à tous les utilisateurs actifs..." />
            <div className="flex gap-2">
              <Button className="gradient-primary"><Send className="w-4 h-4 mr-1" /> Diffuser</Button>
              <Button variant="outline">Programmer</Button>
            </div>
            <p className="text-xs text-muted-foreground">⚠ Action sensible — approbation Super Admin requise.</p>
          </Card>
        </TabsContent>
        <TabsContent value="log" className="mt-4 space-y-2">
          <AdminToolbar placeholder="Rechercher destinataire..." />
          {RECENT.map((r, i) => (
            <Card key={i} className="p-3 flex items-center gap-3">
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium">{r.to}</p>
                <p className="text-xs text-muted-foreground">{r.template} · {r.t}</p>
              </div>
              <StatusBadge status={r.status} />
            </Card>
          ))}
        </TabsContent>
      </Tabs>
    </ModulePage>
  );
}
