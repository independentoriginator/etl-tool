create or replace function f_generate_record_id_from_name(
	i_name text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	md5(${mainSchemaName}.f_string_significant_pomace(i_str => i_name))
$function$;		

comment on function f_generate_record_id_from_name(
	text
) is 'Идентификатор записи из наименования';