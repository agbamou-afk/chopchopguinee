import { NavLink, useLocation } from "react-router-dom";
import {
  LayoutDashboard, Activity, Users, Bike, Store, Wallet, Coins, Tag,
  ClipboardList, UtensilsCrossed, ShoppingBag, LifeBuoy, ShieldAlert,
  MessageSquare, Megaphone, BarChart3, MapPin, ToggleLeft, Settings,
  UserCog, ScrollText, Sparkles, Scale,
} from "lucide-react";
import {
  Sidebar, SidebarContent, SidebarGroup, SidebarGroupContent, SidebarGroupLabel,
  SidebarMenu, SidebarMenuButton, SidebarMenuItem, useSidebar,
} from "@/components/ui/sidebar";
import { AdminModule } from "@/lib/admin/permissions";
import { useAdminAuth } from "@/hooks/useAdminAuth";

type Item = { title: string; url: string; icon: any; module: AdminModule };

const GROUPS: { label: string; items: Item[] }[] = [
  {
    label: "Vue d'ensemble",
    items: [
      { title: "Tableau de bord", url: "/admin", icon: LayoutDashboard, module: "dashboard" },
      { title: "Live Operations", url: "/admin/live", icon: Activity, module: "live_ops" },
    ],
  },
  {
    label: "Opérations",
    items: [
      { title: "Utilisateurs", url: "/admin/users", icon: Users, module: "users" },
      { title: "Chauffeurs", url: "/admin/drivers", icon: Bike, module: "drivers" },
      { title: "Marchands", url: "/admin/merchants", icon: Store, module: "merchants" },
      { title: "Courses & livraisons", url: "/admin/orders", icon: ClipboardList, module: "orders" },
      { title: "Repas", url: "/admin/repas", icon: UtensilsCrossed, module: "repas" },
      { title: "Marché", url: "/admin/marche", icon: ShoppingBag, module: "marche" },
      { title: "Support", url: "/admin/support", icon: LifeBuoy, module: "support" },
      { title: "Fraude / Risque", url: "/admin/risk", icon: ShieldAlert, module: "risk" },
    ],
  },
  {
    label: "Finance",
    items: [
      { title: "Agents de recharge", url: "/admin/vendors", icon: Coins, module: "vendors" },
      { title: "Wallet / Ledger", url: "/admin/wallet", icon: Wallet, module: "wallet" },
      { title: "Réconciliation OM", url: "/admin/wallet/reconciliation", icon: Scale, module: "wallet" },
      { title: "Tarification", url: "/admin/pricing", icon: Tag, module: "pricing" },
      { title: "Rapports", url: "/admin/reports", icon: BarChart3, module: "reports" },
      { title: "Analytique IA", url: "/admin/analytics", icon: Sparkles, module: "analytics" },
    ],
  },
  {
    label: "Croissance",
    items: [
      { title: "Notifications", url: "/admin/notifications", icon: MessageSquare, module: "notifications" },
      { title: "Promotions", url: "/admin/promotions", icon: Megaphone, module: "promotions" },
    ],
  },
  {
    label: "Plateforme",
    items: [
      { title: "Zones", url: "/admin/zones", icon: MapPin, module: "zones" },
      { title: "Feature flags", url: "/admin/flags", icon: ToggleLeft, module: "flags" },
      { title: "Paramètres", url: "/admin/settings", icon: Settings, module: "settings" },
      { title: "Admins", url: "/admin/admins", icon: UserCog, module: "admins" },
      { title: "Audit logs", url: "/admin/audit", icon: ScrollText, module: "audit" },
    ],
  },
];

export function AdminSidebar() {
  const { state, isMobile, setOpenMobile } = useSidebar();
  const collapsed = state === "collapsed";
  const { pathname } = useLocation();
  const { can } = useAdminAuth();
  const isActive = (url: string) =>
    url === "/admin" ? pathname === "/admin" : pathname === url || pathname.startsWith(url + "/");

  const handleNav = () => { if (isMobile) setOpenMobile(false); };

  return (
    <Sidebar collapsible="icon">
      <SidebarContent>
        {GROUPS.map((group) => {
          const visible = group.items.filter((i) => can(i.module));
          if (!visible.length) return null;
          return (
            <SidebarGroup key={group.label}>
              {!collapsed && <SidebarGroupLabel>{group.label}</SidebarGroupLabel>}
              <SidebarGroupContent>
                <SidebarMenu>
                  {visible.map((item) => (
                    <SidebarMenuItem key={item.url}>
                      <SidebarMenuButton asChild isActive={isActive(item.url)}>
                        <NavLink to={item.url} onClick={handleNav} className="flex items-center gap-2">
                          <item.icon className="h-4 w-4" />
                          {!collapsed && <span>{item.title}</span>}
                        </NavLink>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  ))}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          );
        })}
      </SidebarContent>
    </Sidebar>
  );
}