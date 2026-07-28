-- Release freeze: sandbox must be OFF in production.
UPDATE public.feature_flags SET enabled = false, updated_at = now()
WHERE key IN ('om_sandbox_enabled','om_environment') AND enabled = true;