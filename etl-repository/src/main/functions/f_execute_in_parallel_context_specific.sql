create or replace function ${stagingSchemaName}.f_execute_in_parallel_context_specific(
	i_context_name text
	, i_scheduled_task_name text -- 'project_internal_name.scheduled_task_internal_name'
	, i_commands text[]
	, i_iteration_number ${stagingSchemaName}.scheduled_task_subjob.iteration_number%type = 0
	, i_thread_max_count integer = 10
)
returns boolean
language plpgsql
stable
as $function$
begin
	-- Context specific realization
	if i_context_name = 'pgpro_scheduler' then
		perform 
			${mainSchemaName}.f_generate_pgpro_scheduler_subjobs(
				i_scheduled_task_name => i_scheduled_task_name
				, i_iteration_number => i_iteration_number
				, i_commands => i_commands
			);
		return true;
	end if;
	
	return false;
end
$function$;