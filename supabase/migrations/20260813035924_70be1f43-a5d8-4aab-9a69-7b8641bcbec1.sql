WITH s AS (
 SELECT (public._qa_s13_run1()->'results') a, (public._qa_s13_run2()->'results') b,
        (public._qa_s13_run3()->'results') c, (public._qa_s13_run4()->'results') d,
        (public._qa_s13_run5()->'results') e, (public._qa_s13_run6()->'results') f,
        (public._qa_s13_run7()->'results') g),
all13 AS (SELECT (a||b||c||d||e||f||g) j FROM s)
SELECT
 (public._qa_node0_course())->>'total' n0_total,
 (public._qa_node0_course())->>'failed' n0_failed,
 (SELECT jsonb_array_length(j) FROM all13) s13_total,
 (SELECT count(*) FROM all13, jsonb_array_elements(j) e WHERE (e->>'ok')::boolean IS NOT TRUE) s13_failed,
 (SELECT jobid||' '||jobname||' '||schedule||' active='||active FROM cron.job WHERE jobname='chopchop-ride-no-driver-sweep') cron_job,
 (SELECT count(*) FROM cron.job_run_details d2 JOIN cron.job j2 ON j2.jobid=d2.jobid
   WHERE j2.jobname='chopchop-ride-no-driver-sweep' AND d2.status='succeeded' AND d2.start_time > now()-interval '5 minutes') cron_ok_5min,
 (SELECT count(*) FROM public.driver_profiles WHERE status='approved' AND vehicle_type='toktok') approved_toktok,
 (SELECT balance_gnf||'/'||held_gnf FROM public.wallets WHERE party_type='master' LIMIT 1) master,
 (SELECT count(*) FROM public.rides r JOIN auth.users u ON u.id=r.client_id WHERE u.email LIKE 'qa-s13-n1%') n1_residue;