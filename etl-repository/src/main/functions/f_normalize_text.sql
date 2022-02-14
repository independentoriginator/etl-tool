create or replace function f_normalize_text(
	i_name text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	regexp_replace(regexp_replace(i_name, '[\n\r]|\s{2,}', ' ', 'g' ), '[^[:print:]]', '', 'g')
$function$;		