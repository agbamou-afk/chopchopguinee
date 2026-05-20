CREATE POLICY "Customer creates own mission" ON public.missions
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = customer_id);