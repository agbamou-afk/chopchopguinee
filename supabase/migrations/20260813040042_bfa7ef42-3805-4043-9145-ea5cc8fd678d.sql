WITH s AS (
 SELECT public._qa_s13_run1() a, public._qa_s13_run2() b, public._qa_s13_run3() c,
        public._qa_s13_run4() d, public._qa_s13_run5() e, public._qa_s13_run6() f,
        public._qa_s13_run7() g FROM (SELECT 1) z)
SELECT (a->>'total')::int+(b->>'total')::int+(c->>'total')::int+(d->>'total')::int
       +(e->>'total')::int+(f->>'total')::int+(g->>'total')::int AS s13_total,
       (a->>'failed')::int+(b->>'failed')::int+(c->>'failed')::int+(d->>'failed')::int
       +(e->>'failed')::int+(f->>'failed')::int+(g->>'failed')::int AS s13_failed,
       (a->'failures')||(b->'failures')||(c->'failures')||(d->'failures')||(e->'failures')||(f->'failures')||(g->'failures') AS failures
FROM s;