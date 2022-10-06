create or replace function f_integer_min_value(
	i_value anyelement
)
returns anyelement
language sql
immutable
parallel safe
as $function$
/*
	Usage:
	select
	  f_integer_min_value(0::int)
	  , f_integer_max_value(0::int)
	  , f_integer_min_value(0::bigint)
	  , f_integer_max_value(0::bigint)
	;
*/
select 
	((i_value - i_value) - 1) << (8 * pg_column_size(i_value) - 1)
$function$;		