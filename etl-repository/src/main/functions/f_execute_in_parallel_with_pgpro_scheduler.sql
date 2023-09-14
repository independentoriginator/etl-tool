drop function if exists ${stagingSchemaName}.f_execute_in_parallel_with_pgpro_scheduler(
	text
	, text[]
	, integer
	, integer
);

create or replace function ${stagingSchemaName}.f_execute_in_parallel_with_pgpro_scheduler(
	i_scheduled_task_name text -- 'project_internal_name.scheduled_task_internal_name'
	, i_scheduled_task_stage_ord_pos integer
	, i_commands text[]
	, i_iteration_number integer = 0
	, i_thread_max_count integer = 10
)
returns boolean
language plpgsql
stable
as $function$
declare 
	l_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%type;
begin
	l_scheduled_task_stage_id := 
		${mainSchemaName}.f_scheduled_task_stage_id(
			i_scheduled_task_name => i_scheduled_task_name
			, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
		);
	
	if l_scheduled_task_stage_id is null then
		raise exception 'Unknown scheduled task stage specified: %.%', i_scheduled_task_name, i_scheduled_task_stage_ord_pos;
	end if;

	perform 
		${mainSchemaName}.f_generate_pgpro_scheduler_subjobs(
			i_scheduled_task_stage_id => l_scheduled_task_stage_id
			, i_iteration_number => i_iteration_number
			, i_commands => i_commands
		);
	
	return true;
end
$function$;

comment on function ${stagingSchemaName}.f_execute_in_parallel_with_pgpro_scheduler(
	text
	, integer
	, text[]
	, integer
	, integer
) is ' Исполнение перечня команд в параллельном режиме с помощью pgpro_scheduler';