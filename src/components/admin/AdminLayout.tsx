import { Outlet, useNavigate } from "react-router-dom";
import { LogOut, ShieldCheck } from "lucide-react";
import { SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { AdminSidebar } from "./AdminSidebar";
import { AdminGuard } from "./AdminGuard";
import { useAdminAuth } from "@/hooks/useAdminAuth";
import { ROLE_LABELS } from "@/lib/admin/permissions";
import { supabase } from "@/integrations/supabase/client";

export function AdminLayout() {
  const navigate = useNavigate();
  const { user, role } = useAdminAuth();

  const signOut = async () => {
    await supabase.auth.signOut();
    navigate("/auth", { replace: true });
  };

  return (
    <AdminGuard>
      <SidebarProvider>
        <div className="min-h-screen flex w-full bg-muted/30">
          <AdminSidebar />
          <div className="flex-1 flex flex-col min-w-0">
            <header className="h-14 flex items-center gap-3 border-b bg-background px-3">
              <SidebarTrigger />
              <div className="flex items-center gap-2">
                <ShieldCheck className="w-5 h-5 text-primary" />
                <span className="font-bold tracking-tight">CHOP CHOP Admin</span>
              </div>
              <div className="ml-auto flex items-center gap-3">
                {role && (
                  <Badge variant="secondary" className="hidden sm:inline-flex">
                    {ROLE_LABELS[role]}
                  </Badge>
                )}
                <span className="text-xs text-muted-foreground hidden sm:inline">{user?.email}</span>
                <Button size="sm" variant="ghost" onClick={signOut}>
                  <LogOut className="w-4 h-4" />
                </Button>
              </div>
            </header>
            <main className="flex-1 p-4 md:p-6 overflow-auto">
              <Outlet />
            </main>
          </div>
        </div>
      </SidebarProvider>
    </AdminGuard>
  );
}