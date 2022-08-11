create or replace function f_is_scheduler_type_available(
	i_scheduler_type_name ${mainSchemaName}.scheduler_type.internal_name%type
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case 
		when exists (
			select 
				1
			from 
				pg_catalog.pg_extension e
			where 
				e.extname = i_scheduler_type_name
		) then true
		else false
	end 
$function$;		