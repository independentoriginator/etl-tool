create or replace function f_string_significant_pomace(
	i_str text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	lower(regexp_replace(i_str, '\W', '', 'g'))
$function$;		