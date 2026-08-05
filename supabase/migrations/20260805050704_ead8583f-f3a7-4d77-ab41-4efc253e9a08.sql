-- =====================================================================
-- CHOP PAY — Slice 1: canonical double-entry journal layer
-- Convention: postings are SIGNED. debit = positive, credit = negative.
-- Assets/expenses increase with debit (+). Liabilities/revenue/equity
-- increase with credit (-). Every journal MUST sum to exactly 0.
-- =====================================================================

CREATE TABLE public.ledger_accounts (
  code          text PRIMARY KEY,
  name          text NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('asset','liability','revenue','expense','equity')),
  restricted    boolean NOT NULL DEFAULT false,
  description   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.ledger_accounts TO authenticated;
GRANT ALL ON public.ledger_accounts TO service_role;
ALTER TABLE public.ledger_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated read chart of accounts"
  ON public.ledger_accounts FOR SELECT TO authenticated USING (true);

INSERT INTO public.ledger_accounts (code, name, kind, restricted, description) VALUES
  ('L_CUSTOMER_CHOPPAY',      'Customer Chop Pay balance',        'liability', false, 'Customer available liability'),
  ('L_CUSTOMER_HOLD',         'Customer authorised payment hold', 'liability', true,  'Customer funds reserved for an order'),
  ('L_DRIVER_UNRESTRICTED',   'Driver operating balance',         'liability', false, 'Withdrawable driver liability'),
  ('L_DRIVER_PROMO',          'Driver restricted starting credit','liability', true,  'Promotional restricted liability'),
  ('L_HOLD_COMMISSION',       'Driver commission reserve held',   'liability', true,  'Driver funds reserved for commission'),
  ('L_HOLD_COLLATERAL',       'Mission collateral held',          'liability', true,  'Driver funds reserved as collateral'),
  ('L_HOLD_CASH_FUNDING',     'Cash-order merchandise funding held','liability',true, 'Unrestricted driver funds funding merchandise'),
  ('L_HOLD_PLATFORM_FEE',     'Transaction fee reserve held',     'liability', true,  'Driver/customer funds reserved for the platform fee'),
  ('L_HOLD_CASHOUT',          'Pending driver payout',            'liability', true,  'Withdrawable value reserved for an outbound payout'),
  ('L_HOLD_SETTLEMENT',       'Pending merchant settlement',      'liability', true,  'Merchant payable reserved for an outbound settlement'),
  ('L_MERCHANT_PAYABLE',      'Merchant payable',                 'liability', false, 'CHOPCHOP accounts payable to a merchant'),
  ('L_CLAIMS_RESERVE',        'Claims reserve',                   'liability', true,  'Authorised reserve for investigated claims'),
  ('A_CUSTOMER_DEBT',         'Customer cancellation receivable', 'asset',     false, 'Unpaid cancellation debt owed by a customer'),
  ('A_PROVIDER_CLEARING',     'Provider clearing',                'asset',     false, 'Outbound/inbound provider movement awaiting evidence'),
  ('R_COMMISSION',            'Ride commission revenue',          'revenue',   false, null),
  ('R_TRANSACTION_FEE',       'Transaction fee revenue',          'revenue',   false, null),
  ('R_CANCELLATION_FEE',      'Cancellation fee revenue',         'revenue',   false, null),
  ('R_COLLATERAL_LOSS',       'Recovered collateral loss',        'revenue',   false, 'Authorised collateral capture after evidence review'),
  ('E_PROMOTIONAL_CREDIT',    'Promotional credit expense',       'expense',   false, 'Restricted starting-credit issuance'),
  ('E_CLAIMS',                'Claims expense',                   'expense',   false, 'Approved claim compensation'),
  ('E_PROVIDER_FEE',          'Provider fee expense',             'expense',   false, null),
  ('EQ_PLATFORM',             'Platform clearing / equity',       'equity',    false, 'Counterparty for platform-side postings');

-- ---------------------------------------------------------------- journals
CREATE TABLE public.ledger_journals (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_key        text NOT NULL UNIQUE,
  source_module      text NOT NULL,
  source_id          uuid,
  action             text NOT NULL,
  mission_type       text,
  actor_user_id      uuid,
  policy_snapshot    jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_sandbox         boolean NOT NULL DEFAULT false,
  reason             text,
  evidence_ref       text,
  reverses_journal_id uuid REFERENCES public.ledger_journals(id),
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_journals_source ON public.ledger_journals (source_module, source_id);
CREATE INDEX idx_ledger_journals_created ON public.ledger_journals (created_at DESC);

CREATE TABLE public.ledger_postings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_id        uuid NOT NULL REFERENCES public.ledger_journals(id) ON DELETE RESTRICT,
  account_code      text NOT NULL REFERENCES public.ledger_accounts(code),
  amount_gnf        bigint NOT NULL,
  party_type        public.party_type,
  party_user_id     uuid,
  merchant_store_id uuid,
  memo              text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ledger_postings_nonzero CHECK (amount_gnf <> 0)
);
CREATE INDEX idx_ledger_postings_journal ON public.ledger_postings (journal_id);
CREATE INDEX idx_ledger_postings_party ON public.ledger_postings (party_user_id, account_code);
CREATE INDEX idx_ledger_postings_store ON public.ledger_postings (merchant_store_id) WHERE merchant_store_id IS NOT NULL;

GRANT SELECT ON public.ledger_journals TO authenticated;
GRANT SELECT ON public.ledger_postings TO authenticated;
GRANT ALL ON public.ledger_journals TO service_role;
GRANT ALL ON public.ledger_postings TO service_role;

ALTER TABLE public.ledger_journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_postings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parties read their own postings"
  ON public.ledger_postings FOR SELECT TO authenticated
  USING (
    party_user_id = auth.uid()
    OR public.is_god_admin(auth.uid())
    OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
    OR EXISTS (
      SELECT 1 FROM public.merchant_stores ms
       WHERE ms.id = ledger_postings.merchant_store_id
         AND ms.owner_user_id = auth.uid()
    )
  );

CREATE POLICY "Parties read journals touching them"
  ON public.ledger_journals FOR SELECT TO authenticated
  USING (
    public.is_god_admin(auth.uid())
    OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
    OR EXISTS (
      SELECT 1 FROM public.ledger_postings lp
       WHERE lp.journal_id = ledger_journals.id
         AND (lp.party_user_id = auth.uid()
              OR EXISTS (SELECT 1 FROM public.merchant_stores ms
                          WHERE ms.id = lp.merchant_store_id AND ms.owner_user_id = auth.uid()))
    )
  );

-- ------------------------------------------------------------ immutability
CREATE OR REPLACE FUNCTION public._ledger_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'LEDGER_IMMUTABLE: financial journal records cannot be % (use a compensating reversal journal)', lower(TG_OP);
END;
$$;

CREATE TRIGGER trg_ledger_journals_immutable
  BEFORE UPDATE OR DELETE ON public.ledger_journals
  FOR EACH ROW EXECUTE FUNCTION public._ledger_immutable();

CREATE TRIGGER trg_ledger_postings_immutable
  BEFORE UPDATE OR DELETE ON public.ledger_postings
  FOR EACH ROW EXECUTE FUNCTION public._ledger_immutable();

-- ------------------------------------------- deferred zero-sum invariant
CREATE OR REPLACE FUNCTION public._ledger_assert_balanced()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  v_sum bigint;
  v_cnt int;
BEGIN
  SELECT COALESCE(SUM(amount_gnf), 0), count(*) INTO v_sum, v_cnt
    FROM public.ledger_postings WHERE journal_id = NEW.journal_id;
  IF v_cnt < 2 THEN
    RAISE EXCEPTION 'LEDGER_UNBALANCED: journal % has % posting(s); at least 2 required', NEW.journal_id, v_cnt;
  END IF;
  IF v_sum <> 0 THEN
    RAISE EXCEPTION 'LEDGER_UNBALANCED: journal % sums to % GNF, expected 0', NEW.journal_id, v_sum;
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_ledger_balanced
  AFTER INSERT ON public.ledger_postings
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public._ledger_assert_balanced();

-- --------------------------------------------------------- posting helper
-- Internal only. p_lines = jsonb array of
--   {account, amount_gnf (signed), party_type, party_user_id, merchant_store_id, memo}
CREATE OR REPLACE FUNCTION public._ledger_post(
  p_journal_key   text,
  p_source_module text,
  p_source_id     uuid,
  p_action        text,
  p_lines         jsonb,
  p_mission_type  text DEFAULT NULL,
  p_actor         uuid DEFAULT NULL,
  p_policy        jsonb DEFAULT '{}'::jsonb,
  p_is_sandbox    boolean DEFAULT false,
  p_reason        text DEFAULT NULL,
  p_evidence      text DEFAULT NULL,
  p_reverses      uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_j public.ledger_journals;
  v_line jsonb;
  v_sum bigint := 0;
BEGIN
  IF p_journal_key IS NULL OR btrim(p_journal_key) = '' THEN
    RAISE EXCEPTION 'LEDGER_KEY_REQUIRED';
  END IF;

  -- Idempotent replay: return the existing journal, post nothing.
  SELECT * INTO v_j FROM public.ledger_journals WHERE journal_key = p_journal_key;
  IF v_j.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','replayed','journal_id',v_j.id,'journal_key',p_journal_key);
  END IF;

  INSERT INTO public.ledger_journals
    (journal_key, source_module, source_id, action, mission_type, actor_user_id,
     policy_snapshot, is_sandbox, reason, evidence_ref, reverses_journal_id)
  VALUES
    (p_journal_key, p_source_module, p_source_id, p_action, p_mission_type,
     COALESCE(p_actor, auth.uid()), COALESCE(p_policy,'{}'::jsonb),
     COALESCE(p_is_sandbox,false), p_reason, p_evidence, p_reverses)
  ON CONFLICT (journal_key) DO NOTHING
  RETURNING * INTO v_j;

  IF v_j.id IS NULL THEN
    SELECT * INTO v_j FROM public.ledger_journals WHERE journal_key = p_journal_key;
    RETURN jsonb_build_object('status','replayed','journal_id',v_j.id,'journal_key',p_journal_key);
  END IF;

  FOR v_line IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines,'[]'::jsonb)) LOOP
    CONTINUE WHEN COALESCE((v_line->>'amount_gnf')::bigint, 0) = 0;
    INSERT INTO public.ledger_postings
      (journal_id, account_code, amount_gnf, party_type, party_user_id, merchant_store_id, memo)
    VALUES
      (v_j.id, v_line->>'account', (v_line->>'amount_gnf')::bigint,
       NULLIF(v_line->>'party_type','')::public.party_type,
       NULLIF(v_line->>'party_user_id','')::uuid,
       NULLIF(v_line->>'merchant_store_id','')::uuid,
       v_line->>'memo');
    v_sum := v_sum + (v_line->>'amount_gnf')::bigint;
  END LOOP;

  IF v_sum <> 0 THEN
    RAISE EXCEPTION 'LEDGER_UNBALANCED: journal % sums to % GNF, expected 0', p_journal_key, v_sum;
  END IF;

  RETURN jsonb_build_object('status','posted','journal_id',v_j.id,'journal_key',p_journal_key);
END;
$$;

REVOKE ALL ON FUNCTION public._ledger_post(text,text,uuid,text,jsonb,text,uuid,jsonb,boolean,text,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._ledger_post(text,text,uuid,text,jsonb,text,uuid,jsonb,boolean,text,text,uuid) TO service_role;

-- --------------------------------------------------- compensating reversal
CREATE OR REPLACE FUNCTION public._ledger_reverse(
  p_original_key text,
  p_reason       text,
  p_evidence     text DEFAULT NULL,
  p_actor        uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_o public.ledger_journals;
  v_lines jsonb;
BEGIN
  SELECT * INTO v_o FROM public.ledger_journals WHERE journal_key = p_original_key;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'LEDGER_JOURNAL_NOT_FOUND: %', p_original_key; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'LEDGER_REASON_REQUIRED';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'account', account_code,
           'amount_gnf', -amount_gnf,
           'party_type', party_type,
           'party_user_id', party_user_id,
           'merchant_store_id', merchant_store_id,
           'memo', 'reversal: ' || COALESCE(memo,''))), '[]'::jsonb)
    INTO v_lines
    FROM public.ledger_postings WHERE journal_id = v_o.id;

  RETURN public._ledger_post(
    'reverse:' || p_original_key, v_o.source_module, v_o.source_id,
    v_o.action || '_reversed', v_lines, v_o.mission_type,
    COALESCE(p_actor, auth.uid()), v_o.policy_snapshot, v_o.is_sandbox,
    p_reason, p_evidence, v_o.id);
END;
$$;

REVOKE ALL ON FUNCTION public._ledger_reverse(text,text,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._ledger_reverse(text,text,text,uuid) TO service_role;

-- ----------------------------------------------------- reconciliation view
CREATE OR REPLACE VIEW public.ledger_account_totals
WITH (security_invoker = true) AS
  SELECT lp.account_code,
         la.kind,
         la.restricted,
         SUM(lp.amount_gnf)::bigint AS net_debit_gnf,
         count(*)::bigint AS posting_count
    FROM public.ledger_postings lp
    JOIN public.ledger_accounts la ON la.code = lp.account_code
   GROUP BY 1,2,3;

GRANT SELECT ON public.ledger_account_totals TO authenticated;
GRANT SELECT ON public.ledger_account_totals TO service_role;