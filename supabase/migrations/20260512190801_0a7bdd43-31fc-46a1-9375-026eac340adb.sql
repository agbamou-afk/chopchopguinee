ALTER PUBLICATION supabase_realtime ADD TABLE public.rides;
ALTER TABLE public.rides REPLICA IDENTITY FULL;