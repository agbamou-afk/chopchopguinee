DELETE FROM public._qa_s13_results WHERE part = 907;
INSERT INTO public._qa_s13_results(part, result)
VALUES (907, public._qa_node3_repas_r7_tracking_receipt());