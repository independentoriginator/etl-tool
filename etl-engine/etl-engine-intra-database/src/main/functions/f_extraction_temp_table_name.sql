create or replace function f_extraction_temp_table_name(
	i_task_id ${mainSchemaName}.task.id%type
	, i_transfer_name ${mainSchemaName}.transfer.internal_name%type
	, i_is_for_reexec boolean = false
)
returns name
language sql
immutable
as $function$
select 
	('t_' || i_task_id::varchar || '_' || i_transfer_name || case when i_is_for_reexec then '_for_reexec' else '' end)::name
$function$;		