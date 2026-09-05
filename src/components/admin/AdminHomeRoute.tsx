import { Navigate } from "react-router-dom";
import { lazy, Suspense } from "react";
import { useAdminAuth } from "@/hooks/useAdminAuth";

const AdminDashboard = lazy(() => import("@/pages/admin/AdminDashboard"));

/**
 * Landing route for /admin: each staff class lands on the console it is
 * responsible for. God Admin keeps the full dashboard.
 */
export function AdminHomeRoute() {
  const { ready, role } = useAdminAuth();
  if (!ready) return null;
  if (role === "operations_admin") return <Navigate to="/admin/ops" replace />;
  if (role === "finance_admin") return <Navigate to="/admin/finance" replace />;
  return (
    <Suspense fallback={null}>
      <AdminDashboard />
    </Suspense>
  );
}
