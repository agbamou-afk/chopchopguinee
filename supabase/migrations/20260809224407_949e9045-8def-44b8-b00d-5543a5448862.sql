DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.ride_complete(uuid,bigint,integer)'::regprocedure) INTO d;
  d := replace(d, 'public._is_god_admin()', 'public._is_god_admin(v_uid)');
  EXECUTE d;
END $$;