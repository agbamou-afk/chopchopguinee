import { useAuth, AppRole } from "@/contexts/AuthContext";
import { AdminRole, AdminModule, Capability, can } from "@/lib/admin/permissions";

/** Map a unified app role onto the legacy AdminRole used by the permissions map. */
function toAdminRole(roles: AppRole[]): AdminRole | null {
  if (roles.includes("god_admin")) return "god_admin";
  if (roles.includes("operations_admin")) return "operations_admin";
  if (roles.includes("finance_admin")) return "finance_admin";
  // G2: the legacy bare `admin` label carries NO admin authority (mirrors
  // public.admin_role_canonical). The server is authoritative either way.
  return null;
}

/**
 * Thin wrapper around the global AuthContext so existing admin code keeps working.
 * Single source of truth is now `<AuthProvider>`.
 */
export function useAdminAuth() {
  const { ready, user, roles, isAdmin } = useAuth();
  const role = toAdminRole(roles);
  return {
    ready,
    user: user ? { id: user.id, email: user.email ?? null } : null,
    role,
    isAdmin,
    isSuperAdmin: role === "god_admin",
    can: (module: AdminModule, cap: Capability = "view") => can(role, module, cap),
  };
}