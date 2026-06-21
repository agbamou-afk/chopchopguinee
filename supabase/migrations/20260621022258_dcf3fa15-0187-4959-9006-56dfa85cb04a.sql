ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_via text;

CREATE INDEX IF NOT EXISTS idx_admin_users_must_change_password
  ON public.admin_users(user_id) WHERE must_change_password = true;