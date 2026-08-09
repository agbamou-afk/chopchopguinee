CREATE OR REPLACE FUNCTION public._qa_s3_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_msg text; v_ctx text;
BEGIN
  BEGIN
    PERFORM public._qa_s3_inner();
    RETURN jsonb_build_object('error','harness did not raise');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    GET STACKED DIAGNOSTICS v_ctx = PG_EXCEPTION_CONTEXT;
  END;
  IF position('QA_S3_RESULT:' in v_msg) > 0 THEN
    RETURN jsonb_build_object('results', substr(v_msg, position('QA_S3_RESULT:' in v_msg) + 13)::jsonb);
  END IF;
  RETURN jsonb_build_object('fatal', v_msg, 'context', v_ctx);
END $$;