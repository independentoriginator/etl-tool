drop procedure if exists p_execute_task(
	${mainSchemaName}.task.internal_name%type
	, ${mainSchemaName}.project.internal_name%type
	, text
	, text
	, integer
	, integer
);

create or replace procedure p_execute_task(
	i_task_name ${mainSchemaName}.task.internal_name%type
	, i_project_name ${mainSchemaName}.project.internal_name%type
	, i_scheduler_type_name text = null
	, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
	, i_scheduled_task_stage_ord_pos integer = null
	, i_thread_max_count integer = 1
	, i_wait_for_delay_in_seconds integer = 1
)
language plpgsql
as $procedure$
declare 
	l_task_commands text[];
begin
	select
		array_agg(
			format($$
				call ${mainSchemaName}.p_execute_task_transfer_chain(
					i_task_id => %L
					, i_transfer_chain_id => %L
					, i_scheduler_type_name => %L
					, i_scheduled_task_name => %L
					, i_scheduled_task_stage_ord_pos => %L
					, i_thread_max_count => %L
					, i_wait_for_delay_in_seconds => %L
					, i_last_execution_date => %L
				)
				$$
				, ts.task_id 
				, ts.transfer_chain_id
				, i_scheduler_type_name
				, i_scheduled_task_name
				, i_scheduled_task_stage_ord_pos
				, i_thread_max_count
				, i_wait_for_delay_in_seconds
				, ${mainSchemaName}.f_scheduled_task_last_execution_date(
					i_scheduled_task_name => i_scheduled_task_name
				)
			)
			order by 
				chain_order_num
		)
	into 
		l_task_commands
	from (
		select distinct
		 	ts.task_id 
			, ts.transfer_chain_id
			, ts.chain_order_num
		from 
			${mainSchemaName}.v_task_stage ts
		where 
			ts.project_name = i_project_name
			and ts.task_name = i_task_name
	) ts
	;
	
	if l_task_commands is null then
		raise exception 'Unknown task specified or task has no commands: %.%', i_project_name, i_task_name;
	end if;
		
	call ${stagingSchemaName}.p_execute_in_parallel(
		i_commands => l_task_commands
		, i_thread_max_count => i_thread_max_count
		, i_scheduler_type_name => i_scheduler_type_name
		, i_scheduled_task_name => i_scheduled_task_name
		, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
		, i_iteration_number => 0
		, i_wait_for_delay_in_seconds => i_wait_for_delay_in_seconds
	);	
end
$procedure$;			
