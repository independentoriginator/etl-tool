create or replace function f_number_value_limit(
	i_is_negative boolean default false
)
returns numeric
language sql
immutable
parallel safe
as $function$
select 
	(case when i_is_negative = true then -1.0 else 1.0 end) * ((10.0^${type.precision.numeric})-1.0)/(10.0^${type.scale.numeric})
$function$;		