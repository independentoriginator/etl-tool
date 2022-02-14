create or replace function f_string_are_the_same(
	i_left text
	, i_right text
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_left), '') = 
				coalesce(${database.defaultSchemaName}.f_string_significant_pomace(i_right), '') then 
		true
		else false
	end
$function$;		