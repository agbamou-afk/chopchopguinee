import { Outlet, useNavigate } from "react-router-dom";
import { Suspense } from "react";
import { LogOut } from "lucide-react";
import { SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";
import { AdminSidebar } from "./AdminSidebar";
import { AdminGuard } from "./AdminGuard";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { useAuth } from "@/contexts/AuthContext";
import { ROLE_LABELS } from "@/lib/admin/permissions";

export function AdminLayout() {
  const navigate = useNavigate();
  const { user, role } = useAdminAuth();
  const { signOut: signOutGlobal } = useAuth();

  const signOut = async () => {
    await signOutGlobal();
    navigate("/auth", { replace: true });
  };

  return (
    <AdminGuard>
      <SidebarProvider>
        <div
          className="min-h-screen flex w-full admin-shell"
          style={{
            paddingLeft: "env(safe-area-inset-left)",
            paddingRight: "env(safe-area-inset-right)",
            paddingBottom: "env(safe-area-inset-bottom)",
          }}
        >
          <AdminSidebar />
          <div className="flex-1 flex flex-col min-w-0">
            <header
              className="relative h-12 flex items-center gap-3 border-b border-border/70 bg-background/95 backdrop-blur px-3"
              style={{ paddingTop: "env(safe-area-inset-top)" }}
            >
              <SidebarTrigger className="shrink-0" />
              <div className="flex items-baseline gap-2 min-w-0">
                <span className="font-mono text-[11px] tracking-[0.18em] uppercase text-muted-foreground">
                  CHOP · Console
                </span>
                <span className="hidden sm:inline-flex h-1 w-1 rounded-full bg-secondary/80" />
                <span className="hidden sm:inline font-mono text-[10px] tracking-wider uppercase text-muted-foreground/70">
                  ops
                </span>
              </div>
              <div className="ml-auto flex items-center gap-2 shrink-0">
                {role && (
                  <span className="hidden sm:inline-flex items-center gap-1.5 font-mono text-[10px] tracking-wider uppercase text-muted-foreground border border-border/70 rounded px-1.5 py-0.5">
                    <span className="h-1.5 w-1.5 rounded-full bg-primary" />
                    {ROLE_LABELS[role]}
                  </span>
                )}
                <span className="text-[11px] text-muted-foreground hidden md:inline tabular-nums">{user?.email}</span>
                <Button size="sm" variant="ghost" className="h-7 w-7 p-0" onClick={signOut} aria-label="Déconnexion">
                  <LogOut className="w-3.5 h-3.5" />
                </Button>
              </div>
            </header>
            <main className="flex-1 p-3 md:p-5 overflow-auto scrollbar-hide scroll-smooth">
              <Suspense fallback={<div className="p-6 text-sm text-muted-foreground">Chargement…</div>}>
                <Outlet />
              </Suspense>
            </main>
          </div>
        </div>
      </SidebarProvider>
    </AdminGuard>
  );
}