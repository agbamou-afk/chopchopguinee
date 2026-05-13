import { Outlet, useNavigate } from "react-router-dom";
import { Suspense } from "react";
import { LogOut } from "lucide-react";
import { SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { AdminSidebar } from "./AdminSidebar";
import { AdminGuard } from "./AdminGuard";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { useAuth } from "@/contexts/AuthContext";
import { ROLE_LABELS } from "@/lib/admin/permissions";
import { useHasNotch } from "@/hooks/useHasNotch";
import logo from "@/assets/logo.png";

export function AdminLayout() {
  const navigate = useNavigate();
  const { user, role } = useAdminAuth();
  const { signOut: signOutGlobal } = useAuth();
  const hasNotch = useHasNotch();

  const signOut = async () => {
    await signOutGlobal();
    navigate("/auth", { replace: true });
  };

  return (
    <AdminGuard>
      <SidebarProvider>
        <div
          className="min-h-screen flex w-full bg-muted/30"
          style={{
            paddingLeft: "env(safe-area-inset-left)",
            paddingRight: "env(safe-area-inset-right)",
            paddingBottom: "env(safe-area-inset-bottom)",
          }}
        >
          <AdminSidebar />
          <div className="flex-1 flex flex-col min-w-0">
            <header
              className="relative h-16 flex items-center gap-2 border-b bg-background px-3"
              style={{ paddingTop: "env(safe-area-inset-top)" }}
            >
              <SidebarTrigger className="shrink-0 z-10" />

              {/* Logo — centered on standard devices, left-aligned on notched devices */}
              {hasNotch ? (
                <div className="flex items-center gap-2 z-10">
                  <img
                    src={logo}
                    alt="CHOP CHOP"
                    className="h-9 w-auto object-contain mix-blend-multiply dark:mix-blend-screen"
                  />
                  <span className="text-xs font-semibold text-muted-foreground tracking-wide">Admin</span>
                </div>
              ) : (
                <div className="absolute left-1/2 -translate-x-1/2 flex items-center gap-2 pointer-events-none">
                  <img
                    src={logo}
                    alt="CHOP CHOP"
                    className="h-9 w-auto object-contain mix-blend-multiply dark:mix-blend-screen"
                  />
                  <span className="text-xs font-semibold text-muted-foreground tracking-wide hidden sm:inline">
                    Admin
                  </span>
                </div>
              )}

              <div className="ml-auto flex items-center gap-2 z-10 shrink-0">
                {role && (
                  <Badge variant="secondary" className="hidden sm:inline-flex">
                    {ROLE_LABELS[role]}
                  </Badge>
                )}
                <span className="text-xs text-muted-foreground hidden md:inline">{user?.email}</span>
                <Button size="sm" variant="ghost" onClick={signOut}>
                  <LogOut className="w-4 h-4" />
                </Button>
              </div>
            </header>
            <main className="flex-1 p-4 md:p-6 overflow-auto scrollbar-hide scroll-smooth">
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