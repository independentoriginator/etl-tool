create or replace function f_normalize_text(
	i_text text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	nullif(nullif(btrim(regexp_replace(regexp_replace(i_text, '[\n\r]|\s{2,}', ' ', 'g' ), '[^[:print:]]', '', 'g')), '-'), '');
$function$;		