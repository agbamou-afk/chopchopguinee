
-- ============================================================
-- Enums
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.party_type AS ENUM ('client','driver','merchant','agent','master');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.wallet_status AS ENUM ('active','frozen','closed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.txn_type AS ENUM (
    'topup','payment','refund','commission','payout',
    'hold','capture','release','transfer','adjustment'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.txn_status AS ENUM ('pending','completed','failed','reversed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.topup_status AS ENUM ('pending','confirmed','expired','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Extend app_role enum with party roles (idempotent)
DO $$ BEGIN
  ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'client';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'driver';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'merchant';
EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'agent';
EXCEPTION WHEN others THEN NULL; END $$;

-- ============================================================
-- Generic timestamp trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================================================
-- profiles
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  phone text UNIQUE,
  full_name text,
  avatar_url text,
  language text NOT NULL DEFAULT 'fr',
  pin_hash text,
  kyc_level int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own profile" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins view all profiles" ON public.profiles
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users insert own profile" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins manage profiles" ON public.profiles
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- wallets
-- ============================================================
CREATE TABLE IF NOT EXISTS public.wallets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid,                          -- null for master wallet
  party_type public.party_type NOT NULL,
  balance_gnf bigint NOT NULL DEFAULT 0,
  held_gnf bigint NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'GNF',
  status public.wallet_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT wallet_balance_nonneg CHECK (balance_gnf >= 0 AND held_gnf >= 0),
  CONSTRAINT wallet_owner_unique UNIQUE (owner_user_id, party_type)
);
-- Only one master wallet
CREATE UNIQUE INDEX IF NOT EXISTS wallets_master_singleton
  ON public.wallets ((1)) WHERE party_type = 'master';

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own wallets" ON public.wallets
  FOR SELECT TO authenticated USING (auth.uid() = owner_user_id);
CREATE POLICY "Admins view all wallets" ON public.wallets
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage wallets" ON public.wallets
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_wallets_updated_at
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- agent_profiles
-- ============================================================
CREATE TABLE IF NOT EXISTS public.agent_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  business_name text NOT NULL,
  location text,
  latitude double precision,
  longitude double precision,
  prepaid_float_gnf bigint NOT NULL DEFAULT 0,
  daily_limit_gnf bigint NOT NULL DEFAULT 5000000,
  commission_rate numeric(5,4) NOT NULL DEFAULT 0.0100, -- 1%
  status public.wallet_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.agent_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active agents" ON public.agent_profiles
  FOR SELECT TO authenticated USING (status = 'active');
CREATE POLICY "Agents update own profile" ON public.agent_profiles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Admins manage agent profiles" ON public.agent_profiles
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_agent_profiles_updated_at
  BEFORE UPDATE ON public.agent_profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- wallet_transactions
-- ============================================================
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE,
  type public.txn_type NOT NULL,
  status public.txn_status NOT NULL DEFAULT 'pending',
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  from_wallet_id uuid REFERENCES public.wallets(id),
  to_wallet_id uuid REFERENCES public.wallets(id),
  related_user_id uuid,
  related_entity text,    -- e.g. 'ride:123', 'order:456'
  description text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_txn_from ON public.wallet_transactions(from_wallet_id);
CREATE INDEX IF NOT EXISTS idx_txn_to ON public.wallet_transactions(to_wallet_id);
CREATE INDEX IF NOT EXISTS idx_txn_user ON public.wallet_transactions(related_user_id);
CREATE INDEX IF NOT EXISTS idx_txn_created ON public.wallet_transactions(created_at DESC);

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own transactions" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (
    auth.uid() = related_user_id
    OR EXISTS (SELECT 1 FROM public.wallets w WHERE w.id = wallet_transactions.from_wallet_id AND w.owner_user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.wallets w WHERE w.id = wallet_transactions.to_wallet_id AND w.owner_user_id = auth.uid())
  );
CREATE POLICY "Admins view all transactions" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage transactions" ON public.wallet_transactions
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============================================================
-- topup_requests (agent cash-in)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.topup_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE,
  client_user_id uuid NOT NULL,
  agent_user_id uuid NOT NULL,
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  confirmation_code text NOT NULL,
  status public.topup_status NOT NULL DEFAULT 'pending',
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '15 minutes'),
  confirmed_at timestamptz,
  cancelled_reason text,
  transaction_id uuid REFERENCES public.wallet_transactions(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_topup_client ON public.topup_requests(client_user_id);
CREATE INDEX IF NOT EXISTS idx_topup_agent ON public.topup_requests(agent_user_id);

ALTER TABLE public.topup_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Client views own topups" ON public.topup_requests
  FOR SELECT TO authenticated USING (auth.uid() = client_user_id);
CREATE POLICY "Agent views own topups" ON public.topup_requests
  FOR SELECT TO authenticated USING (auth.uid() = agent_user_id);
CREATE POLICY "Admins view all topups" ON public.topup_requests
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage topups" ON public.topup_requests
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_topup_updated_at
  BEFORE UPDATE ON public.topup_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- Auto-create profile + client wallet on new auth user
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, phone, full_name)
  VALUES (
    NEW.id,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name')
  )
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.wallets (owner_user_id, party_type)
  VALUES (NEW.id, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- Seed master wallet (singleton)
-- ============================================================
INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf)
SELECT NULL, 'master', 0
WHERE NOT EXISTS (SELECT 1 FROM public.wallets WHERE party_type = 'master');
