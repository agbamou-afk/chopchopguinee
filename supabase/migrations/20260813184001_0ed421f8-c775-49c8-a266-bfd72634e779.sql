CREATE OR REPLACE FUNCTION public._ride_mission_type(p_mode text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE p_mode
           WHEN 'toktok' THEN 'bonbonna'
           WHEN 'auto'   THEN 'taxi'
           ELSE 'ride'
         END
$function$;