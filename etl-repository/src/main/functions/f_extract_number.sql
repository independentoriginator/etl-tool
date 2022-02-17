create or replace function f_extract_number(
	i_str_as_prefix_number_suffix text
)
returns text[]
language sql
immutable
parallel safe
as $function$
select 
	regexp_match(
		i_str_as_prefix_number_suffix, 
		'(?:(.*?)((?:-\s*)*(?:(?:\d\s)*(?:\d*[.,]*\d+)+\s*(?:\d*[.,]*\d+)*)+(?:[eE]{1}[+-]*\d+)*)(.*)){1,1}'
	);
$function$;		