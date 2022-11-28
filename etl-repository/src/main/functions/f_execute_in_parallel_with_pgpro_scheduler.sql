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
	select 
		s.id
	into 
		l_scheduled_task_stage_id
	from 
		${mainSchemaName}.scheduled_task t
	join ${mainSchemaName}.project p
		on p.id = t.project_id
		and p.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\1')
	join ${mainSchemaName}.scheduler_type st
		on st.id = t.scheduler_type_id
		and st.internal_name = 'pgpro_scheduler'
	join ${mainSchemaName}.scheduled_task_stage s
		on s.scheduled_task_id = t.id
		and s.ordinal_position = i_scheduled_task_stage_ord_pos
	where
		t.internal_name = regexp_replace(i_scheduled_task_name, '(.+)\.(.+)', '\2')
	;
	
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