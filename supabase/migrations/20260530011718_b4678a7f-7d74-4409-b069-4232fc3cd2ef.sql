
-- 1. Extend admin_role enum (additive, safe)
ALTER TYPE public.admin_role ADD VALUE IF NOT EXISTS 'god_admin';
ALTER TYPE public.admin_role ADD VALUE IF NOT EXISTS 'operations_admin';
ALTER TYPE public.admin_role ADD VALUE IF NOT EXISTS 'support_admin';
