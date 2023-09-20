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
	, i_scheduled_task_stage_ord_pos integer = 0
	, i_thread_max_count integer = 1
	, i_wait_for_delay_in_seconds integer = 1
)
language plpgsql
as $procedure$
declare 
	l_task_commands text[];
	l_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%type;
begin
	select
		array_agg(
			format($$
				call ${mainSchemaName}.p_execute_task_transfer_chain(
					i_task_id => %s
					, i_transfer_chain_id => %s
					, i_is_deletion_stage => %L::boolean
					, i_scheduler_type_name => %L
					, i_scheduled_task_name => %L
					, i_scheduled_task_stage_ord_pos => %s
					, i_thread_max_count => %s
					, i_wait_for_delay_in_seconds => %s
					, i_last_execution_date => %L
				)
				$$
				, ts.task_id 
				, ts.transfer_chain_id
				, ts.is_deletion_stage
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
				ts.chain_order_num
				, ts.is_deletion_stage desc
		)
	into 
		l_task_commands
	from (
		select distinct
		 	ts.task_id 
			, ts.transfer_chain_id
			, ts.is_deletion_stage
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

	l_scheduled_task_stage_id := 
		${mainSchemaName}.f_scheduled_task_stage_id(
			i_scheduled_task_name => i_scheduled_task_name
			, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
		);
	
	if l_scheduled_task_stage_id is null then
		raise exception 'Unknown scheduled task stage specified: %.%', i_scheduled_task_name, i_scheduled_task_stage_ord_pos;
	end if;

	-- Cancel incompleted subjobs from the previous session
	perform ${mainSchemaName}.f_cancel_pgpro_scheduler_subjobs(
		i_scheduled_task_stage_id => l_scheduled_task_stage_id
	);

	-- Clean staging subjob list
	delete from 
		${stagingSchemaName}.scheduled_task_subjob
	where 
		scheduled_task_stage_id in (
			select 
				prev_session_task_stage.id
			from 
				${mainSchemaName}.scheduled_task_stage task_stage
			join ${mainSchemaName}.scheduled_task_stage prev_session_task_stage
				on prev_session_task_stage.scheduled_task_id = task_stage.scheduled_task_id
				and prev_session_task_stage.ordinal_position >= task_stage.ordinal_position
				and prev_session_task_stage.is_disabled = false
			where
				task_stage.id = l_scheduled_task_stage_id
		)
	;
		
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

comment on procedure p_execute_task(
	${mainSchemaName}.task.internal_name%type
	, ${mainSchemaName}.project.internal_name%type
	, text
	, text
	, integer
	, integer
	, integer
) is 'Исполнение задачи';
