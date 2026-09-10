CREATE OR REPLACE FUNCTION public._pra_valid_phone(_provider text, _phone text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN _provider IN ('orange_money','mtn_money') THEN _phone ~ '^\+224[0-9]{9}$'
    ELSE coalesce(btrim(_phone),'') <> ''
  END;
$$;
REVOKE EXECUTE ON FUNCTION public._pra_valid_phone(text,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._pra_governed_write_guard() FROM PUBLIC, anon, authenticated;