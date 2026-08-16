ALTER FUNCTION public._qa_node3_repas_r7_semantics() RENAME TO _qa_node3_repas_r7_semantics_fxcore;
ALTER FUNCTION public._qa_node3_repas_r7_readtruth() RENAME TO _qa_node3_repas_r7_readtruth_fxcore;
ALTER FUNCTION public._qa_node3_repas_r7_ext() RENAME TO _qa_node3_repas_r7_ext_fxcore;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_semantics()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r7_semantics_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_readtruth()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r7_readtruth_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_ext()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r7_ext_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_semantics() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_semantics_fxcore() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth_fxcore() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext_fxcore() FROM PUBLIC, anon, authenticated;