CREATE TABLE public.support_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID,
  message TEXT NOT NULL CHECK (char_length(message) <= 250 AND char_length(message) > 0),
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- Anyone (incl. anonymous) can submit a support message
CREATE POLICY "Anyone can submit a support message"
ON public.support_messages
FOR INSERT
TO public
WITH CHECK (
  (auth.uid() IS NULL AND user_id IS NULL)
  OR (auth.uid() = user_id)
);

-- Users can view their own messages; admins can view all
CREATE POLICY "Users view own support messages"
ON public.support_messages
FOR SELECT
TO authenticated
USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'));

-- Admins can update (mark resolved)
CREATE POLICY "Admins can update support messages"
ON public.support_messages
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));