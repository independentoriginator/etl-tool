create or replace function f_number_value_limit(
	i_is_negative boolean default false
	, i_precision integer default ${type.precision.numeric}
	, i_scale integer default ${type.scale.numeric}
)
returns numeric
language sql
immutable
parallel safe
as $function$
select 
	(case when i_is_negative = true then -1.0 else 1.0 end) * ((10.0^i_precision)-1.0)/(10.0^i_scale)
$function$;

comment on function f_number_value_limit(
	boolean
	, integer
	, integer
) is 'Граничное значение числа';