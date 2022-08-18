create or replace function ${stagingSchemaName}.f_execute_in_parallel_context_specific(
	i_scheduled_task_name text -- 'project_internal_name.scheduled_task_internal_name'
	, i_commands text[]
	, i_iteration_number integer = 0
	, i_thread_max_count integer = 10
)
returns boolean
language plpgsql
stable
as $function$
declare 
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%type;
	l_scheduler_type_name ${mainSchemaName}.scheduler_type.internal_name%type;
begin
	select 
		t.id
		, st.internal_name
	into 
		l_scheduled_task_id
		, l_scheduler_type_name
	from 
		${mainSchemaName}.scheduled_task t
	join ${mainSchemaName}.project p
		on p.id = t.project_id
	join ${mainSchemaName}.scheduler_type st
		on st.id = t.scheduler_type_id
	where
		p.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\1')
		and t.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\2')
	;
	
	if l_scheduled_task_id is null then
		raise exception 'Unknown scheduled task specified: %', i_scheduled_task_name;
	end if;

	-- Context specific realization
	if l_scheduler_type_name = 'pgpro_scheduler' then
		perform 
			${mainSchemaName}.f_generate_pgpro_scheduler_subjobs(
				i_scheduled_task_id => l_scheduled_task_id
				, i_iteration_number => i_iteration_number
				, i_commands => i_commands
			);
		return true;
	end if;
	
	return false;
end
$function$;