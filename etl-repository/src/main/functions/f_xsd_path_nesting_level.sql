create or replace function f_xsd_path_nesting_level(
	i_path text
)
returns integer
language sql
stable
as $function$
select 
	count(*)::integer
from 
	regexp_matches(
		i_path
		, '/([^/]*)'
		, 'g'
	)
$function$;		