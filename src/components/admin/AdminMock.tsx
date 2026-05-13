import { ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Search } from "lucide-react";

export function StatGrid({ items }: { items: { label: string; value: string; icon?: any; tone?: string }[] }) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
      {items.map((k) => (
        <Card key={k.label} className="p-4 transition-all hover:shadow-soft animate-fade-in">
          {k.icon && <k.icon className={`w-4 h-4 ${k.tone ?? "text-muted-foreground"}`} />}
          <p className="text-xs text-muted-foreground mt-2">{k.label}</p>
          <p className="text-lg font-bold mt-1">{k.value}</p>
        </Card>
      ))}
    </div>
  );
}

export function AdminToolbar({ placeholder, right }: { placeholder: string; right?: ReactNode }) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <div className="relative flex-1 min-w-[180px]">
        <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder={placeholder} className="pl-9 bg-card" />
      </div>
      {right}
    </div>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const map: Record<string, string> = {
    active: "bg-emerald-100 text-emerald-700",
    online: "bg-emerald-100 text-emerald-700",
    pending: "bg-amber-100 text-amber-800",
    open: "bg-amber-100 text-amber-800",
    investigating: "bg-blue-100 text-blue-700",
    resolved: "bg-emerald-100 text-emerald-700",
    completed: "bg-emerald-100 text-emerald-700",
    suspended: "bg-rose-100 text-rose-700",
    offline: "bg-muted text-muted-foreground",
    failed: "bg-rose-100 text-rose-700",
    reversed: "bg-purple-100 text-purple-700",
    escalated: "bg-rose-100 text-rose-700",
    high: "bg-rose-100 text-rose-700",
    medium: "bg-amber-100 text-amber-800",
    low: "bg-emerald-100 text-emerald-700",
  };
  return <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${map[status] ?? "bg-muted"}`}>{status}</span>;
}

export function DataTable({ columns, rows }: { columns: string[]; rows: (ReactNode[])[] }) {
  return (
    <Card className="p-0 overflow-hidden">
      <div className="overflow-x-auto scrollbar-hide">
        <table className="w-full text-sm">
          <thead className="bg-muted/50">
            <tr className="text-left">{columns.map((c) => <th key={c} className="p-3 font-medium text-xs uppercase tracking-wide text-muted-foreground">{c}</th>)}</tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr><td colSpan={columns.length} className="p-10 text-center text-muted-foreground text-sm">Aucune donnée</td></tr>
            ) : rows.map((r, i) => (
              <tr key={i} className="border-t hover:bg-muted/30 transition-colors">
                {r.map((c, j) => <td key={j} className="p-3">{c}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

export function FilterChip({ label, active, onClick }: { label: string; active?: boolean; onClick?: () => void }) {
  return (
    <button onClick={onClick}
      className={`text-xs px-3 py-1.5 rounded-full border transition-all ${active ? "bg-primary text-primary-foreground border-primary" : "bg-card hover:bg-muted"}`}>
      {label}
    </button>
  );
}

export { Badge, Button };
