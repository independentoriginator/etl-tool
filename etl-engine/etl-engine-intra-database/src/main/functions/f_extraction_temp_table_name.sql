drop function if exists f_extraction_temp_table_name(
	${mainSchemaName}.task.id%type
	, ${mainSchemaName}.transfer.internal_name%type
	, boolean
);

drop function if exists f_extraction_temp_table_name(
	${mainSchemaName}.task.id%type
	, ${mainSchemaName}.transfer.id%type
	, boolean
);

create or replace function f_extraction_temp_table_name(
	i_task_id ${mainSchemaName}.task.id%type
	, i_transfer_id ${mainSchemaName}.transfer.id%type
	, i_chunk_id text = null
	, i_is_for_reexec boolean = false
)
returns name
language sql
immutable
as $function$
select 
	(
		't_'::text
		|| i_task_id::text 
		|| '_' || i_transfer_id::text
		|| coalesce('_' || md5(i_chunk_id), '')
		|| case when i_is_for_reexec then '_for_reexec' else '' end
	)::name
$function$;		

comment on function f_extraction_temp_table_name(
	${mainSchemaName}.task.id%type
	, ${mainSchemaName}.transfer.id%type
	, text
	, boolean
) is 'Имя временной таблицы для извлечения';