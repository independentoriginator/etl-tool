create or replace function f_extraction_temp_table_name(
	i_transfer_id ${mainSchemaName}.transfer.id%type
	, i_extraction_name ${mainSchemaName}.source.internal_name%type
)
returns name
language sql
immutable
as $function$
select 
	('t_' || i_transfer_id::varchar || '_' || i_extraction_name)::name
$function$;		