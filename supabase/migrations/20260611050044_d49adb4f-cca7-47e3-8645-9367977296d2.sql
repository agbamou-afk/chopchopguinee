
-- Phase 1c: ride_complete inserts type='ride_earning' on the cash path,
-- but the txn_type enum is missing this label, which makes every cash-ride
-- completion error out. Add the missing label. Idempotent.
ALTER TYPE public.txn_type ADD VALUE IF NOT EXISTS 'ride_earning';
