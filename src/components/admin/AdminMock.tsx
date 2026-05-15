import { ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Search } from "lucide-react";

export function StatGrid({ items }: { items: { label: string; value: string; icon?: any; tone?: string }[] }) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
      {items.map((k) => (
        <div key={k.label} className="admin-card p-3">
          <div className="flex items-center justify-between">
            <span className="admin-eyebrow">{k.label}</span>
            {k.icon && <k.icon className={`w-3.5 h-3.5 ${k.tone ?? "text-muted-foreground/70"}`} />}
          </div>
          <p className="text-[17px] font-semibold mt-1.5 tabular-nums tracking-tight">{k.value}</p>
        </div>
      ))}
    </div>
  );
}

export function AdminToolbar({ placeholder, right }: { placeholder: string; right?: ReactNode }) {
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <div className="relative flex-1 min-w-[180px]">
        <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder={placeholder} className="pl-8 h-8 bg-card text-[13px]" />
      </div>
      {right}
    </div>
  );
}

export function StatusBadge({ status }: { status: string }) {
  const map: Record<string, string> = {
    active: "chip-ok", online: "chip-ok", resolved: "chip-ok", completed: "chip-ok", low: "chip-ok",
    pending: "chip-warn", open: "chip-warn", medium: "chip-warn",
    investigating: "chip-info",
    suspended: "chip-err", failed: "chip-err", escalated: "chip-err", high: "chip-err",
    offline: "chip-mute",
    reversed: "chip-violet",
  };
  return <span className={`chip-status ${map[status] ?? "chip-mute"}`}>{status}</span>;
}

export function DataTable({ columns, rows }: { columns: string[]; rows: (ReactNode[])[] }) {
  return (
    <div className="admin-card p-0 overflow-hidden">
      <div className="overflow-x-auto scrollbar-hide">
        <table className="w-full text-[13px] tabular-nums">
          <thead className="bg-muted/40">
            <tr className="text-left">{columns.map((c) => <th key={c} className="px-3 py-2 font-mono text-[10px] uppercase tracking-[0.14em] text-muted-foreground/80 border-b border-border/70">{c}</th>)}</tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr><td colSpan={columns.length} className="px-3 py-8 text-center text-muted-foreground text-[13px]">Aucune donnée</td></tr>
            ) : rows.map((r, i) => (
              <tr key={i} className="border-t border-border/50 hover:bg-muted/40 transition-colors">
                {r.map((c, j) => <td key={j} className="px-3 py-2 align-middle">{c}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function FilterChip({ label, active, onClick }: { label: string; active?: boolean; onClick?: () => void }) {
  return (
    <button onClick={onClick}
      className={`text-[11px] font-medium px-2.5 py-1 rounded-md border transition-colors ${active ? "bg-primary/10 text-primary border-primary/40" : "bg-card hover:bg-muted border-border/70 text-foreground/75"}`}>
      {label}
    </button>
  );
}

export { Badge, Button };
