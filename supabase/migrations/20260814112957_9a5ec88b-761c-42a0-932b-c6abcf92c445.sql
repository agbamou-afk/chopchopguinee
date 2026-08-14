ALTER FUNCTION public._repas_custody_issue(uuid, text, uuid) SET search_path TO 'public', 'extensions';
ALTER FUNCTION public._repas_custody_consume(uuid, text, text, uuid) SET search_path TO 'public', 'extensions';
ALTER FUNCTION public._repas_custody_hash(text, text) SET search_path TO 'public', 'extensions';