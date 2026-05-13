import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { BarChart3, Download, TrendingUp, Wallet } from "lucide-react";
import { LineChart, Line, ResponsiveContainer, XAxis, YAxis, Tooltip, BarChart, Bar } from "recharts";

const RIDES = Array.from({ length: 14 }).map((_, i) => ({ d: `J${i + 1}`, v: 800 + Math.round(Math.random() * 1200) }));
const REV = Array.from({ length: 14 }).map((_, i) => ({ d: `J${i + 1}`, v: 8 + Math.round(Math.random() * 12) }));

export default function ReportsAdmin() {
  return (
    <ModulePage module="reports" title="Rapports" subtitle="Performance, revenus et exports"
      actions={<Button size="sm" variant="outline"><Download className="w-4 h-4 mr-1" /> Exporter CSV</Button>}>
      <StatGrid items={[
        { label: "CA 30j", value: "248 M GNF", icon: TrendingUp, tone: "text-emerald-600" },
        { label: "Commissions 30j", value: "37 M GNF", icon: Wallet, tone: "text-primary" },
        { label: "Courses 30j", value: "48 920", icon: BarChart3, tone: "text-blue-600" },
        { label: "Utilisateurs actifs", value: "8 932", icon: TrendingUp, tone: "text-amber-600" },
      ]} />
      <div className="grid md:grid-cols-2 gap-4">
        <Card className="p-5">
          <p className="text-sm font-semibold mb-3">Courses / jour (14j)</p>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={RIDES}>
              <XAxis dataKey="d" tick={{ fontSize: 10 }} /><YAxis tick={{ fontSize: 10 }} /><Tooltip />
              <Line type="monotone" dataKey="v" stroke="hsl(var(--primary))" strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </Card>
        <Card className="p-5">
          <p className="text-sm font-semibold mb-3">Revenus / jour (M GNF)</p>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={REV}>
              <XAxis dataKey="d" tick={{ fontSize: 10 }} /><YAxis tick={{ fontSize: 10 }} /><Tooltip />
              <Bar dataKey="v" fill="hsl(var(--secondary))" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>
      </div>
    </ModulePage>
  );
}
