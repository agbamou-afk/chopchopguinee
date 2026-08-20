CREATE TABLE IF NOT EXISTS public._qa_r8_out (id bigserial primary key, ran_at timestamptz not null default now(), res jsonb);
GRANT ALL ON public._qa_r8_out TO service_role;
ALTER TABLE public._qa_r8_out ENABLE ROW LEVEL SECURITY;
DELETE FROM public._qa_r8_out;
INSERT INTO public._qa_r8_out(res) VALUES (public._qa_node4_marche_r8());