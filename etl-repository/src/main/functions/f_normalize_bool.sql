create or replace function f_normalize_bool(
	i_raw_value text
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when i_raw_value ~* '^[\''\"\s]*1|true|t|yes|y|on|да[\''\"\s]*$' then true 
		when i_raw_value ~* '^[\''\"\s]*0|false|f|no|n|off|нет[\''\"\s]*$' then false
		else null::boolean 
	end
$function$;		