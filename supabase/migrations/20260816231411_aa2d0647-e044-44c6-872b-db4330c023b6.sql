-- ============================================================
-- NODE 4 — MARCHÉ R6: CHOPCHOP STAPLES CATALOG (second commerce rail)
-- System-managed staples vocabulary. NOT marketplace_listings.
-- ============================================================

-- ---------- 1. TABLES ----------
CREATE TABLE public.marche_staple_categories (
  code text PRIMARY KEY,
  name_fr text NOT NULL,
  sort_order int NOT NULL DEFAULT 100,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.marche_staple_categories TO service_role;
ALTER TABLE public.marche_staple_categories ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.marche_staple_commodities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  category_code text NOT NULL REFERENCES public.marche_staple_categories(code),
  name_fr text NOT NULL,
  short_label_fr text,
  description_fr text,
  aliases text[] NOT NULL DEFAULT '{}',
  unit_family text NOT NULL,
  icon_key text,
  sort_order int NOT NULL DEFAULT 100,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_staple_commodity_unit_family_chk
    CHECK (unit_family IN ('mass','volume','count','bundle')),
  CONSTRAINT marche_staple_commodity_code_shape_chk
    CHECK (code ~ '^[a-z][a-z0-9_]{1,48}$')
);
GRANT ALL ON public.marche_staple_commodities TO service_role;
ALTER TABLE public.marche_staple_commodities ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.marche_staple_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commodity_id uuid NOT NULL REFERENCES public.marche_staple_commodities(id) ON DELETE RESTRICT,
  code text NOT NULL,
  name_fr text NOT NULL,
  grade_note_fr text,
  is_default boolean NOT NULL DEFAULT false,
  sort_order int NOT NULL DEFAULT 100,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_staple_variant_code_shape_chk
    CHECK (code ~ '^[a-z][a-z0-9_]{1,48}$')
);
CREATE UNIQUE INDEX marche_staple_variant_code_unique
  ON public.marche_staple_variants(commodity_id, code);
GRANT ALL ON public.marche_staple_variants TO service_role;
ALTER TABLE public.marche_staple_variants ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.marche_staple_purchase_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  variant_id uuid NOT NULL REFERENCES public.marche_staple_variants(id) ON DELETE RESTRICT,
  code text NOT NULL,
  sale_unit text NOT NULL,
  label_fr text NOT NULL,
  normalization_kind text NOT NULL,
  canonical_base_unit text,
  canonical_quantity numeric(14,4),
  min_qty numeric(12,3) NOT NULL DEFAULT 1,
  max_qty numeric(12,3) NOT NULL DEFAULT 10,
  step_qty numeric(12,3) NOT NULL DEFAULT 1,
  sort_order int NOT NULL DEFAULT 100,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_staple_option_code_shape_chk
    CHECK (code ~ '^[a-z][a-z0-9_]{1,48}$'),
  CONSTRAINT marche_staple_option_norm_kind_chk
    CHECK (normalization_kind IN ('exact','unit_native','non_comparable')),
  CONSTRAINT marche_staple_option_base_unit_chk
    CHECK (canonical_base_unit IS NULL OR canonical_base_unit IN ('kg','l','piece'))
);
CREATE UNIQUE INDEX marche_staple_option_code_unique
  ON public.marche_staple_purchase_options(variant_id, code);
GRANT ALL ON public.marche_staple_purchase_options TO service_role;
ALTER TABLE public.marche_staple_purchase_options ENABLE ROW LEVEL SECURITY;

-- ---------- 2. VALIDATION / IMMUTABILITY GUARDS ----------
CREATE OR REPLACE FUNCTION public.marche_staple_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at := now();
  IF TG_OP = 'UPDATE' AND NEW.code IS DISTINCT FROM OLD.code THEN
    RAISE EXCEPTION 'STAPLE_CODE_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_marche_staple_category_touch BEFORE UPDATE ON public.marche_staple_categories
  FOR EACH ROW EXECUTE FUNCTION public.marche_staple_touch();
CREATE TRIGGER trg_marche_staple_commodity_touch BEFORE UPDATE ON public.marche_staple_commodities
  FOR EACH ROW EXECUTE FUNCTION public.marche_staple_touch();
CREATE TRIGGER trg_marche_staple_variant_touch BEFORE UPDATE ON public.marche_staple_variants
  FOR EACH ROW EXECUTE FUNCTION public.marche_staple_touch();
CREATE TRIGGER trg_marche_staple_option_touch BEFORE UPDATE ON public.marche_staple_purchase_options
  FOR EACH ROW EXECUTE FUNCTION public.marche_staple_touch();

CREATE OR REPLACE FUNCTION public.marche_staple_option_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_span numeric;
BEGIN
  IF NEW.min_qty IS NULL OR NEW.min_qty <= 0 THEN
    RAISE EXCEPTION 'STAPLE_MIN_QTY_INVALID';
  END IF;
  IF NEW.step_qty IS NULL OR NEW.step_qty <= 0 THEN
    RAISE EXCEPTION 'STAPLE_STEP_QTY_INVALID';
  END IF;
  IF NEW.max_qty IS NULL OR NEW.max_qty < NEW.min_qty THEN
    RAISE EXCEPTION 'STAPLE_MAX_QTY_INVALID';
  END IF;
  v_span := NEW.max_qty - NEW.min_qty;
  IF (v_span % NEW.step_qty) <> 0 THEN
    RAISE EXCEPTION 'STAPLE_QTY_RANGE_NOT_STEP_ALIGNED';
  END IF;

  IF NEW.normalization_kind = 'exact' THEN
    IF NEW.canonical_base_unit IS NULL THEN
      RAISE EXCEPTION 'STAPLE_UNKNOWN_BASE_UNIT';
    END IF;
    IF NEW.canonical_quantity IS NULL OR NEW.canonical_quantity <= 0 THEN
      RAISE EXCEPTION 'STAPLE_EXACT_REQUIRES_POSITIVE_FACTOR';
    END IF;
  ELSE
    -- unit_native and non_comparable must never pretend to carry a cross-unit factor.
    IF NEW.canonical_base_unit IS NOT NULL OR NEW.canonical_quantity IS NOT NULL THEN
      RAISE EXCEPTION 'STAPLE_NON_EXACT_CANNOT_NORMALIZE';
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_marche_staple_option_guard
  BEFORE INSERT OR UPDATE ON public.marche_staple_purchase_options
  FOR EACH ROW EXECUTE FUNCTION public.marche_staple_option_guard();

-- ---------- 3. AUTHORITY ----------
CREATE OR REPLACE FUNCTION public.marche_staple_can_manage(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT _user IS NOT NULL AND public._is_ops_or_god_admin(_user);
$$;
REVOKE ALL ON FUNCTION public.marche_staple_can_manage(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._marche_staple_require_admin()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v uuid := auth.uid();
BEGIN
  IF v IS NULL OR NOT public.marche_staple_can_manage(v) THEN
    RAISE EXCEPTION 'STAPLE_ADMIN_ONLY';
  END IF;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public._marche_staple_require_admin() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._marche_staple_audit(
  p_actor uuid, p_action text, p_target_type text, p_target_id text, p_after jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (p_actor, 'marche', p_action, p_target_type, p_target_id, p_after);
$$;
REVOKE ALL ON FUNCTION public._marche_staple_audit(uuid,text,text,text,jsonb) FROM PUBLIC, anon, authenticated;

-- ---------- 4. PUBLIC READ MODEL (sanitized, role-helper free) ----------
CREATE OR REPLACE VIEW public.v_marche_staple_public AS
SELECT
  c.id            AS commodity_id,
  c.code          AS commodity_code,
  c.name_fr       AS commodity_name_fr,
  c.short_label_fr,
  c.description_fr,
  c.aliases,
  c.unit_family,
  c.icon_key,
  c.sort_order    AS commodity_sort,
  cat.code        AS category_code,
  cat.name_fr     AS category_name_fr,
  cat.sort_order  AS category_sort,
  v.id            AS variant_id,
  v.code          AS variant_code,
  v.name_fr       AS variant_name_fr,
  v.grade_note_fr,
  v.is_default    AS variant_is_default,
  v.sort_order    AS variant_sort,
  o.id            AS option_id,
  o.code          AS option_code,
  o.sale_unit,
  o.label_fr      AS option_label_fr,
  o.normalization_kind,
  o.canonical_base_unit,
  o.canonical_quantity,
  o.min_qty, o.max_qty, o.step_qty,
  o.sort_order    AS option_sort
FROM public.marche_staple_commodities c
JOIN public.marche_staple_categories cat ON cat.code = c.category_code AND cat.is_active
JOIN public.marche_staple_variants v ON v.commodity_id = c.id AND v.is_active
JOIN public.marche_staple_purchase_options o ON o.variant_id = v.id AND o.is_active
WHERE c.is_active;

REVOKE ALL ON public.v_marche_staple_public FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.marche_staple_categories_public()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'sort_order', x->>'code'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'code', cat.code, 'name_fr', cat.name_fr, 'sort_order', cat.sort_order,
      'commodity_count', count(DISTINCT p.commodity_id)) AS x
    FROM public.marche_staple_categories cat
    JOIN public.v_marche_staple_public p ON p.category_code = cat.code
    WHERE cat.is_active
    GROUP BY cat.code, cat.name_fr, cat.sort_order
  ) s;
$$;
GRANT EXECUTE ON FUNCTION public.marche_staple_categories_public() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.marche_staples_discover(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_limit int DEFAULT 60,
  p_offset int DEFAULT 0)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH base AS (
    SELECT DISTINCT commodity_id, commodity_code, commodity_name_fr, short_label_fr,
           description_fr, aliases, unit_family, icon_key, commodity_sort,
           category_code, category_name_fr, category_sort
    FROM public.v_marche_staple_public p
    WHERE (p_category IS NULL OR p.category_code = p_category)
      AND (
        p_search IS NULL OR btrim(p_search) = '' OR
        p.commodity_name_fr ILIKE '%'||btrim(p_search)||'%' OR
        p.commodity_code ILIKE '%'||btrim(p_search)||'%' OR
        EXISTS (SELECT 1 FROM unnest(p.aliases) a WHERE a ILIKE '%'||btrim(p_search)||'%')
      )
  ), page AS (
    SELECT * FROM base
    ORDER BY category_sort, commodity_sort, commodity_name_fr, commodity_code
    LIMIT GREATEST(COALESCE(p_limit,60),0) OFFSET GREATEST(COALESCE(p_offset,0),0)
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'commodity_id', b.commodity_id,
      'commodity_code', b.commodity_code,
      'name_fr', b.commodity_name_fr,
      'short_label_fr', b.short_label_fr,
      'description_fr', b.description_fr,
      'aliases', to_jsonb(b.aliases),
      'unit_family', b.unit_family,
      'icon_key', b.icon_key,
      'category_code', b.category_code,
      'category_name_fr', b.category_name_fr,
      'option_count', (SELECT count(*) FROM public.v_marche_staple_public q WHERE q.commodity_id = b.commodity_id),
      'sale_units', (SELECT COALESCE(jsonb_agg(DISTINCT q.option_label_fr), '[]'::jsonb)
                       FROM public.v_marche_staple_public q WHERE q.commodity_id = b.commodity_id)
    )
    ORDER BY b.category_sort, b.commodity_sort, b.commodity_name_fr, b.commodity_code
  ), '[]'::jsonb) FROM page b;
$$;
GRANT EXECUTE ON FUNCTION public.marche_staples_discover(text,text,int,int) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.marche_staple_get(p_commodity_code text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN count(*) = 0 THEN NULL ELSE
    jsonb_build_object(
      'commodity_code', min(p.commodity_code),
      'name_fr', min(p.commodity_name_fr),
      'short_label_fr', min(p.short_label_fr),
      'description_fr', min(p.description_fr),
      'unit_family', min(p.unit_family),
      'icon_key', min(p.icon_key),
      'category_code', min(p.category_code),
      'category_name_fr', min(p.category_name_fr),
      'aliases', to_jsonb(COALESCE(min(p.aliases), '{}'::text[])),
      'variants', (
        SELECT COALESCE(jsonb_agg(vv ORDER BY vv->>'sort_order', vv->>'variant_code'), '[]'::jsonb) FROM (
          SELECT jsonb_build_object(
            'variant_code', q.variant_code,
            'name_fr', q.variant_name_fr,
            'grade_note_fr', q.grade_note_fr,
            'is_default', q.variant_is_default,
            'sort_order', q.variant_sort,
            'purchase_options', (
              SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'option_code', o.option_code,
                'sale_unit', o.sale_unit,
                'label_fr', o.option_label_fr,
                'normalization_kind', o.normalization_kind,
                'canonical_base_unit', o.canonical_base_unit,
                'canonical_quantity', o.canonical_quantity,
                'min_qty', o.min_qty, 'max_qty', o.max_qty, 'step_qty', o.step_qty
              ) ORDER BY o.option_sort, o.option_code), '[]'::jsonb)
              FROM public.v_marche_staple_public o WHERE o.variant_id = q.variant_id)
          ) AS vv
          FROM (SELECT DISTINCT variant_id, variant_code, variant_name_fr, grade_note_fr,
                       variant_is_default, variant_sort
                  FROM public.v_marche_staple_public
                 WHERE commodity_code = p_commodity_code) q
        ) s)
    ) END
  FROM public.v_marche_staple_public p
  WHERE p.commodity_code = p_commodity_code;
$$;
GRANT EXECUTE ON FUNCTION public.marche_staple_get(text) TO anon, authenticated;

-- Admin read (includes inactive rows + internal metadata)
CREATE OR REPLACE FUNCTION public.marche_staples_admin()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._marche_staple_require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'commodity_id', c.id, 'code', c.code, 'name_fr', c.name_fr,
      'category_code', c.category_code, 'unit_family', c.unit_family,
      'aliases', to_jsonb(c.aliases), 'sort_order', c.sort_order,
      'is_active', c.is_active, 'created_at', c.created_at, 'updated_at', c.updated_at,
      'variants', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'variant_id', v.id, 'code', v.code, 'name_fr', v.name_fr,
          'is_default', v.is_default, 'is_active', v.is_active,
          'options', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
              'option_id', o.id, 'code', o.code, 'sale_unit', o.sale_unit,
              'label_fr', o.label_fr, 'normalization_kind', o.normalization_kind,
              'canonical_base_unit', o.canonical_base_unit,
              'canonical_quantity', o.canonical_quantity,
              'min_qty', o.min_qty, 'max_qty', o.max_qty, 'step_qty', o.step_qty,
              'is_active', o.is_active) ORDER BY o.sort_order, o.code), '[]'::jsonb)
            FROM public.marche_staple_purchase_options o WHERE o.variant_id = v.id)
        ) ORDER BY v.sort_order, v.code), '[]'::jsonb)
        FROM public.marche_staple_variants v WHERE v.commodity_id = c.id)
    ) ORDER BY c.sort_order, c.code)
    FROM public.marche_staple_commodities c), '[]'::jsonb);
END $$;
GRANT EXECUTE ON FUNCTION public.marche_staples_admin() TO authenticated;

-- ---------- 5. ADMIN MUTATION RPCs ----------
CREATE OR REPLACE FUNCTION public.marche_staple_commodity_upsert(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid; v_code text; v_id uuid; v_row public.marche_staple_commodities;
BEGIN
  v_actor := public._marche_staple_require_admin();
  v_code := lower(btrim(COALESCE(p->>'code','')));
  IF v_code = '' THEN RAISE EXCEPTION 'STAPLE_CODE_REQUIRED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.marche_staple_categories
                  WHERE code = p->>'category_code') THEN
    RAISE EXCEPTION 'STAPLE_UNKNOWN_CATEGORY';
  END IF;

  SELECT id INTO v_id FROM public.marche_staple_commodities WHERE code = v_code;
  IF v_id IS NULL THEN
    IF COALESCE((p->>'update_only')::boolean, false) THEN
      RAISE EXCEPTION 'STAPLE_UNKNOWN_COMMODITY';
    END IF;
    INSERT INTO public.marche_staple_commodities
      (code, category_code, name_fr, short_label_fr, description_fr, aliases,
       unit_family, icon_key, sort_order, is_active)
    VALUES (v_code, p->>'category_code', p->>'name_fr', p->>'short_label_fr',
       p->>'description_fr',
       COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p->'aliases','[]'::jsonb))), '{}'),
       COALESCE(p->>'unit_family','mass'), p->>'icon_key',
       COALESCE((p->>'sort_order')::int, 100),
       COALESCE((p->>'is_active')::boolean, true))
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.marche_staple_commodities SET
      category_code = COALESCE(p->>'category_code', category_code),
      name_fr = COALESCE(p->>'name_fr', name_fr),
      short_label_fr = COALESCE(p->>'short_label_fr', short_label_fr),
      description_fr = COALESCE(p->>'description_fr', description_fr),
      aliases = CASE WHEN p ? 'aliases'
        THEN ARRAY(SELECT jsonb_array_elements_text(p->'aliases')) ELSE aliases END,
      unit_family = COALESCE(p->>'unit_family', unit_family),
      icon_key = COALESCE(p->>'icon_key', icon_key),
      sort_order = COALESCE((p->>'sort_order')::int, sort_order)
    WHERE id = v_id RETURNING * INTO v_row;
  END IF;

  PERFORM public._marche_staple_audit(v_actor, 'staple_commodity_upsert', 'staple_commodity',
    v_row.id::text, jsonb_build_object('code', v_row.code));
  RETURN jsonb_build_object('ok', true, 'commodity_id', v_row.id, 'code', v_row.code);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'STAPLE_COMMODITY_CODE_DUPLICATE';
END $$;
REVOKE ALL ON FUNCTION public.marche_staple_commodity_upsert(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_staple_commodity_upsert(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.marche_staple_variant_upsert(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid; v_cid uuid; v_code text; v_id uuid; v_row public.marche_staple_variants;
BEGIN
  v_actor := public._marche_staple_require_admin();
  SELECT id INTO v_cid FROM public.marche_staple_commodities WHERE code = p->>'commodity_code';
  IF v_cid IS NULL THEN RAISE EXCEPTION 'STAPLE_UNKNOWN_COMMODITY'; END IF;
  v_code := lower(btrim(COALESCE(p->>'code','')));
  IF v_code = '' THEN RAISE EXCEPTION 'STAPLE_CODE_REQUIRED'; END IF;

  SELECT id INTO v_id FROM public.marche_staple_variants WHERE commodity_id = v_cid AND code = v_code;
  IF v_id IS NULL THEN
    INSERT INTO public.marche_staple_variants
      (commodity_id, code, name_fr, grade_note_fr, is_default, sort_order, is_active)
    VALUES (v_cid, v_code, p->>'name_fr', p->>'grade_note_fr',
      COALESCE((p->>'is_default')::boolean,false), COALESCE((p->>'sort_order')::int,100),
      COALESCE((p->>'is_active')::boolean,true))
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.marche_staple_variants SET
      name_fr = COALESCE(p->>'name_fr', name_fr),
      grade_note_fr = COALESCE(p->>'grade_note_fr', grade_note_fr),
      is_default = COALESCE((p->>'is_default')::boolean, is_default),
      sort_order = COALESCE((p->>'sort_order')::int, sort_order)
    WHERE id = v_id RETURNING * INTO v_row;
  END IF;

  PERFORM public._marche_staple_audit(v_actor, 'staple_variant_upsert', 'staple_variant',
    v_row.id::text, jsonb_build_object('code', v_row.code));
  RETURN jsonb_build_object('ok', true, 'variant_id', v_row.id, 'code', v_row.code);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'STAPLE_VARIANT_CODE_DUPLICATE';
END $$;
REVOKE ALL ON FUNCTION public.marche_staple_variant_upsert(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_staple_variant_upsert(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.marche_staple_option_upsert(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid; v_vid uuid; v_code text; v_id uuid;
        v_row public.marche_staple_purchase_options; v_kind text; v_base text; v_qty numeric;
BEGIN
  v_actor := public._marche_staple_require_admin();
  SELECT v.id INTO v_vid
    FROM public.marche_staple_variants v
    JOIN public.marche_staple_commodities c ON c.id = v.commodity_id
   WHERE c.code = p->>'commodity_code' AND v.code = p->>'variant_code';
  IF v_vid IS NULL THEN RAISE EXCEPTION 'STAPLE_UNKNOWN_VARIANT'; END IF;

  v_code := lower(btrim(COALESCE(p->>'code','')));
  IF v_code = '' THEN RAISE EXCEPTION 'STAPLE_CODE_REQUIRED'; END IF;
  v_kind := COALESCE(p->>'normalization_kind','exact');
  IF v_kind NOT IN ('exact','unit_native','non_comparable') THEN
    RAISE EXCEPTION 'STAPLE_UNKNOWN_NORMALIZATION_KIND';
  END IF;
  v_base := NULLIF(btrim(COALESCE(p->>'canonical_base_unit','')),'');
  v_qty := NULLIF(p->>'canonical_quantity','')::numeric;
  IF v_base IS NOT NULL AND v_base NOT IN ('kg','l','piece') THEN
    RAISE EXCEPTION 'STAPLE_UNKNOWN_BASE_UNIT';
  END IF;
  IF v_qty IS NOT NULL AND v_qty <= 0 THEN
    RAISE EXCEPTION 'STAPLE_INVALID_CONVERSION_FACTOR';
  END IF;

  SELECT id INTO v_id FROM public.marche_staple_purchase_options
   WHERE variant_id = v_vid AND code = v_code;
  IF v_id IS NULL THEN
    INSERT INTO public.marche_staple_purchase_options
      (variant_id, code, sale_unit, label_fr, normalization_kind, canonical_base_unit,
       canonical_quantity, min_qty, max_qty, step_qty, sort_order, is_active)
    VALUES (v_vid, v_code, COALESCE(p->>'sale_unit', v_code), COALESCE(p->>'label_fr', v_code),
       v_kind, v_base, v_qty,
       COALESCE((p->>'min_qty')::numeric, 1),
       COALESCE((p->>'max_qty')::numeric, 10),
       COALESCE((p->>'step_qty')::numeric, 1),
       COALESCE((p->>'sort_order')::int, 100),
       COALESCE((p->>'is_active')::boolean, true))
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.marche_staple_purchase_options SET
      sale_unit = COALESCE(p->>'sale_unit', sale_unit),
      label_fr = COALESCE(p->>'label_fr', label_fr),
      normalization_kind = v_kind,
      canonical_base_unit = v_base,
      canonical_quantity = v_qty,
      min_qty = COALESCE((p->>'min_qty')::numeric, min_qty),
      max_qty = COALESCE((p->>'max_qty')::numeric, max_qty),
      step_qty = COALESCE((p->>'step_qty')::numeric, step_qty),
      sort_order = COALESCE((p->>'sort_order')::int, sort_order)
    WHERE id = v_id RETURNING * INTO v_row;
  END IF;

  PERFORM public._marche_staple_audit(v_actor, 'staple_option_upsert', 'staple_option',
    v_row.id::text, jsonb_build_object('code', v_row.code, 'kind', v_row.normalization_kind));
  RETURN jsonb_build_object('ok', true, 'option_id', v_row.id, 'code', v_row.code);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'STAPLE_OPTION_CODE_DUPLICATE';
END $$;
REVOKE ALL ON FUNCTION public.marche_staple_option_upsert(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_staple_option_upsert(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.marche_staple_set_active(
  p_kind text, p_id uuid, p_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid; v_n int;
BEGIN
  v_actor := public._marche_staple_require_admin();
  IF p_kind = 'commodity' THEN
    UPDATE public.marche_staple_commodities SET is_active = p_active WHERE id = p_id;
  ELSIF p_kind = 'variant' THEN
    UPDATE public.marche_staple_variants SET is_active = p_active WHERE id = p_id;
  ELSIF p_kind = 'option' THEN
    UPDATE public.marche_staple_purchase_options SET is_active = p_active WHERE id = p_id;
  ELSE
    RAISE EXCEPTION 'STAPLE_UNKNOWN_TARGET_KIND';
  END IF;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RAISE EXCEPTION 'STAPLE_TARGET_NOT_FOUND'; END IF;
  PERFORM public._marche_staple_audit(v_actor, 'staple_set_active', p_kind, p_id::text,
    jsonb_build_object('is_active', p_active));
  RETURN jsonb_build_object('ok', true, 'kind', p_kind, 'id', p_id, 'is_active', p_active);
END $$;
REVOKE ALL ON FUNCTION public.marche_staple_set_active(text,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_staple_set_active(text,uuid,boolean) TO authenticated;

-- ---------- 6. STARTER TAXONOMY SEED (production, idempotent) ----------
INSERT INTO public.marche_staple_categories(code, name_fr, sort_order) VALUES
  ('cereals_starch','Céréales & féculents',10),
  ('oils_condiments','Huiles & condiments',20),
  ('vegetables_leaves','Légumes & feuilles',30),
  ('meat_poultry','Viandes & volailles',40),
  ('fish','Poissons',50),
  ('flour_sugar','Farines & sucre',60),
  ('dairy_breakfast','Lait & petit-déjeuner',70),
  ('bakery','Pain & boulangerie',80),
  ('water_drinks','Eau & boissons essentielles',90),
  ('hygiene_home','Hygiène & maison',100),
  ('fuel','Combustibles',110)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.marche_staple_commodities
  (code, category_code, name_fr, short_label_fr, aliases, unit_family, sort_order) VALUES
  ('rice','cereals_starch','Riz','Riz',ARRAY['riz','malo','rice'],'mass',10),
  ('potato','cereals_starch','Pommes de terre','Pomme de terre',ARRAY['pomme de terre','patate','potato'],'mass',20),
  ('cooking_oil','oils_condiments','Huile','Huile',ARRAY['huile','tulu','oil'],'volume',10),
  ('salt','oils_condiments','Sel','Sel',ARRAY['sel','salt'],'mass',20),
  ('chili','oils_condiments','Piment','Piment',ARRAY['piment','kani','pepper'],'mass',30),
  ('onion','vegetables_leaves','Oignons','Oignon',ARRAY['oignon','onion','jabaré'],'mass',10),
  ('tomato','vegetables_leaves','Tomates','Tomate',ARRAY['tomate','tomato'],'mass',20),
  ('sweet_potato_leaf','vegetables_leaves','Feuilles de patate','Feuille de patate',ARRAY['feuille de patate','feuilles de patate','patate feuille'],'bundle',30),
  ('cassava_leaf','vegetables_leaves','Feuilles de manioc','Feuille de manioc',ARRAY['feuille de manioc','feuilles de manioc','saka saka'],'bundle',40),
  ('chicken','meat_poultry','Poulet','Poulet',ARRAY['poulet','chicken'],'count',10),
  ('meat','meat_poultry','Viande','Viande',ARRAY['viande','boeuf','meat'],'mass',20),
  ('smoked_fish','fish','Poisson fumé','Poisson fumé',ARRAY['poisson fume','poisson fumé','fumé'],'count',10),
  ('dried_fish','fish','Poisson séché','Poisson séché',ARRAY['poisson seche','poisson séché','séché'],'mass',20),
  ('flour','flour_sugar','Farine','Farine',ARRAY['farine','flour'],'mass',10),
  ('sugar','flour_sugar','Sucre','Sucre',ARRAY['sucre','sugar'],'mass',20),
  ('milk','dairy_breakfast','Lait','Lait',ARRAY['lait','milk'],'volume',10),
  ('bread','bakery','Pain','Pain',ARRAY['pain','bread','tapalapa'],'count',10),
  ('water','water_drinks','Eau','Eau',ARRAY['eau','water'],'volume',10),
  ('soap','hygiene_home','Savon','Savon',ARRAY['savon','soap'],'count',10),
  ('charcoal','fuel','Charbon','Charbon',ARRAY['charbon','charbon de bois','coal'],'mass',10)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr, grade_note_fr, is_default, sort_order)
SELECT c.id, x.code, x.name_fr, x.note, x.is_default, x.sort_order
FROM (VALUES
  ('rice','local','Riz local','Production locale',false,20),
  ('rice','imported','Riz importé','Riz importé courant',true,10),
  ('potato','general','Pommes de terre',NULL,true,10),
  ('cooking_oil','general','Huile alimentaire',NULL,true,10),
  ('salt','general','Sel',NULL,true,10),
  ('chili','general','Piment',NULL,true,10),
  ('onion','general','Oignons',NULL,true,10),
  ('tomato','general','Tomates',NULL,true,10),
  ('sweet_potato_leaf','general','Feuilles de patate',NULL,true,10),
  ('cassava_leaf','general','Feuilles de manioc',NULL,true,10),
  ('chicken','general','Poulet',NULL,true,10),
  ('meat','general','Viande',NULL,true,10),
  ('smoked_fish','general','Poisson fumé',NULL,true,10),
  ('dried_fish','general','Poisson séché',NULL,true,10),
  ('flour','general','Farine',NULL,true,10),
  ('sugar','general','Sucre',NULL,true,10),
  ('milk','general','Lait',NULL,true,10),
  ('bread','general','Pain',NULL,true,10),
  ('water','general','Eau',NULL,true,10),
  ('soap','general','Savon',NULL,true,10),
  ('charcoal','general','Charbon de bois',NULL,true,10)
) AS x(commodity_code, code, name_fr, note, is_default, sort_order)
JOIN public.marche_staple_commodities c ON c.code = x.commodity_code
ON CONFLICT DO NOTHING;

INSERT INTO public.marche_staple_purchase_options
  (variant_id, code, sale_unit, label_fr, normalization_kind, canonical_base_unit,
   canonical_quantity, min_qty, max_qty, step_qty, sort_order)
SELECT v.id, x.code, x.sale_unit, x.label_fr, x.kind, x.base, x.qty, x.mn, x.mx, x.st, x.sort_order
FROM (VALUES
  ('rice','local','kg','kg','Au kilo','exact','kg',1::numeric,1::numeric,50::numeric,1::numeric,10),
  ('rice','local','sac_25kg','sac_25kg','Sac de 25 kg','exact','kg',25,1,10,1,20),
  ('rice','imported','kg','kg','Au kilo','exact','kg',1,1,50,1,10),
  ('rice','imported','sac_25kg','sac_25kg','Sac de 25 kg','exact','kg',25,1,10,1,20),
  ('potato','general','kg','kg','Au kilo','exact','kg',1,1,50,1,10),
  ('cooking_oil','general','litre','litre','Au litre','exact','l',1,1,20,1,10),
  ('cooking_oil','general','bidon_5l','bidon_5l','Bidon de 5 L','exact','l',5,1,10,1,20),
  ('salt','general','kg','kg','Au kilo','exact','kg',1,1,25,1,10),
  ('chili','general','kg','kg','Au kilo','exact','kg',1,1,10,1,10),
  ('chili','general','tas','tas','Tas (taille variable)','non_comparable',NULL,NULL,1,10,1,20),
  ('onion','general','kg','kg','Au kilo','exact','kg',1,1,50,1,10),
  ('onion','general','sac_25kg','sac_25kg','Sac de 25 kg','exact','kg',25,1,5,1,20),
  ('tomato','general','kg','kg','Au kilo','exact','kg',1,1,30,1,10),
  ('sweet_potato_leaf','general','botte','botte','La botte','unit_native',NULL,NULL,1,20,1,10),
  ('cassava_leaf','general','botte','botte','La botte','unit_native',NULL,NULL,1,20,1,10),
  ('chicken','general','piece','piece','À la pièce','exact','piece',1,1,10,1,10),
  ('meat','general','kg','kg','Au kilo','exact','kg',1,1,20,1,10),
  ('smoked_fish','general','piece','piece','À la pièce','exact','piece',1,1,20,1,10),
  ('dried_fish','general','kg','kg','Au kilo','exact','kg',1,1,10,1,10),
  ('flour','general','kg','kg','Au kilo','exact','kg',1,1,50,1,10),
  ('flour','general','sac_50kg','sac_50kg','Sac de 50 kg','exact','kg',50,1,5,1,20),
  ('sugar','general','kg','kg','Au kilo','exact','kg',1,1,50,1,10),
  ('milk','general','litre','litre','Au litre','exact','l',1,1,20,1,10),
  ('bread','general','piece','piece','À la pièce','exact','piece',1,1,20,1,10),
  ('water','general','bouteille_1_5l','bouteille_1_5l','Bouteille 1,5 L','exact','l',1.5,1,24,1,10),
  ('water','general','pack_6x1_5l','pack_6x1_5l','Pack de 6 × 1,5 L','exact','l',9,1,10,1,20),
  ('soap','general','piece','piece','À la pièce','exact','piece',1,1,20,1,10),
  ('charcoal','general','kg','kg','Au kilo','exact','kg',1,1,50,1,10),
  ('charcoal','general','sac','sac','Sac (poids non déclaré)','non_comparable',NULL,NULL,1,5,1,20)
) AS x(commodity_code, variant_code, code, sale_unit, label_fr, kind, base, qty, mn, mx, st, sort_order)
JOIN public.marche_staple_commodities c ON c.code = x.commodity_code
JOIN public.marche_staple_variants v ON v.commodity_id = c.id AND v.code = x.variant_code
ON CONFLICT DO NOTHING;