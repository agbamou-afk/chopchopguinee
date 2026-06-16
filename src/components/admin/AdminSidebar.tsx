import { NavLink, useLocation } from "react-router-dom";
import {
  LayoutDashboard, Activity, Users, Bike, Store, Wallet, Coins, Tag,
  ClipboardList, UtensilsCrossed, ShoppingBag, LifeBuoy, ShieldAlert, Smartphone,
  MessageSquare, Megaphone, BarChart3, MapPin, ToggleLeft, Settings,
  UserCog, ScrollText, Sparkles, Scale, Radar, Users2, Map, Compass, Route,
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
      { title: "Pilot Command", url: "/admin/pilot-command", icon: Radar, module: "dashboard" },
    ],
  },
  {
    label: "Opérations",
    items: [
      { title: "Utilisateurs", url: "/admin/users", icon: Users, module: "users" },
      { title: "Chauffeurs", url: "/admin/drivers", icon: Bike, module: "drivers" },
      { title: "Groupes chauffeurs", url: "/admin/driver-groups", icon: Users2, module: "driver_groups" },
      { title: "Marchands", url: "/admin/merchants", icon: Store, module: "merchants" },
      { title: "Courses & livraisons", url: "/admin/orders", icon: ClipboardList, module: "orders" },
      { title: "Repas", url: "/admin/repas", icon: UtensilsCrossed, module: "repas" },
      { title: "Paiements Repas", url: "/admin/repas/payments", icon: Wallet, module: "repas" },
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
      { title: "Comptes OM", url: "/admin/wallet/reconciliation?tab=accounts", icon: Smartphone, module: "wallet" },
      { title: "Paiements (intents)", url: "/admin/payments", icon: Coins, module: "payments" },
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
  {
    label: "Carte",
    items: [
      { title: "Zones de service", url: "/admin/map/zones", icon: Map, module: "zones" },
      { title: "Lieux", url: "/admin/map/places", icon: Compass, module: "zones" },
      { title: "Tarifs moto", url: "/admin/map/tarifs", icon: Route, module: "zones" },
      { title: "Doublons lieux", url: "/admin/map/duplicates", icon: Compass, module: "zones" },
    ],
  },
];

export function AdminSidebar() {
  const { state, isMobile, setOpenMobile } = useSidebar();
  const collapsed = state === "collapsed";
  const { pathname, search } = useLocation();
  const { can } = useAdminAuth();
  const isActive = (url: string) => {
    const [path, query] = url.split("?");
    const currentTab = new URLSearchParams(search).get("tab");
    if (path === "/admin") return pathname === "/admin";
    const pathMatch = pathname === path || pathname.startsWith(path + "/");
    if (!pathMatch) return false;
    if (query) {
      const want = new URLSearchParams(query).get("tab");
      return currentTab === want;
    }
    // For the bare path, only active when no tab param is set OR when the
    // current tab is not one we expose as a separate sidebar entry.
    return currentTab !== "accounts";
  };

  const handleNav = () => { if (isMobile) setOpenMobile(false); };

  return (
    <Sidebar collapsible="icon">
      <SidebarContent className="gap-1 py-2">
        {GROUPS.map((group) => {
          const visible = group.items.filter((i) => can(i.module));
          if (!visible.length) return null;
          return (
            <SidebarGroup key={group.label} className="py-1">
              {!collapsed && (
                <SidebarGroupLabel className="font-mono text-[10px] tracking-[0.16em] uppercase text-muted-foreground/70 px-2 h-6">
                  {group.label}
                </SidebarGroupLabel>
              )}
              <SidebarGroupContent>
                <SidebarMenu className="gap-0.5">
                  {visible.map((item) => (
                    <SidebarMenuItem key={item.url}>
                      <SidebarMenuButton
                        asChild
                        isActive={isActive(item.url)}
                        className="h-7 text-[12.5px] data-[active=true]:bg-primary/10 data-[active=true]:text-primary data-[active=true]:font-medium"
                      >
                        <NavLink to={item.url} onClick={handleNav} className="flex items-center gap-2">
                          <item.icon className="h-3.5 w-3.5 shrink-0" />
                          {!collapsed && <span className="truncate">{item.title}</span>}
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