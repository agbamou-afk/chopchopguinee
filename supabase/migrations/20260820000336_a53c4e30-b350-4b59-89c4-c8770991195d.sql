DELETE FROM public._qa_r8_out;
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','r65','res', public._qa_node4_marche_r65()));
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','r5','res', public._qa_node4_marche_r5()));
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','r8','res', public._qa_node4_marche_r8()));
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','repas_r5_core','res', public._qa_node3_repas_r5_runtime_core()));