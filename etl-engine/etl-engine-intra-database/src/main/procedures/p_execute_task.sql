drop procedure if exists 
	p_execute_task(
		${mainSchemaName}.task.internal_name%type
		, ${mainSchemaName}.project.internal_name%type
		, text
		, text
		, integer
		, integer
	)
;

drop procedure if exists 
	p_execute_task(
		${mainSchemaName}.task.internal_name%type
		, ${mainSchemaName}.project.internal_name%type
		, text
		, text
		, integer
		, integer
		, integer
	)
;

create or replace procedure 
	p_execute_task(
		i_task_name ${mainSchemaName}.task.internal_name%type
		, i_project_name ${mainSchemaName}.project.internal_name%type
		, i_scheduler_type_name text = null
		, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
		, i_scheduled_task_stage_ord_pos integer = 0
		, i_thread_max_count integer = 1
		, i_wait_for_delay_in_seconds integer = 10
		, i_max_run_time interval = '8 hours'
	)
language plpgsql
as $procedure$
declare 
	l_exception_descr text;
	l_exception_detail text;
	l_exception_hint text;
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%type := 
		${mainSchemaName}.f_scheduled_task_id(
			i_scheduled_task_name => i_scheduled_task_name
		)
	;
	l_scheduled_task_stage_id ${mainSchemaName}.scheduled_task_stage.id%type;
	l_polling_interval interval := make_interval(secs => i_wait_for_delay_in_seconds);
begin
	if l_scheduled_task_id is not null then
		call
			${mainSchemaName}.p_publish_scheduled_task_monitoring_event(
				i_scheduled_task_id => l_scheduled_task_id
				, i_event_type_name => 'launch'
				, i_event_status_name => 'success'
				, i_event_message => null
			)
		;
	end if
	;

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

	if i_thread_max_count > 1 
		and exists (
			select 
				1
			from 
				${mainSchemaName}.v_task_stage ts
			where 
				ts.project_name = i_project_name
				and ts.task_name = i_task_name
				and ts.are_del_ins_stages_separated 
		)
	then
		raise exception
			'Separated deletion and insertion stages cannot be executed in multithreaded mode'
		;
	end if
	;

	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => 
				format(
					$sql$
					select
						format($$
							call 
								${mainSchemaName}.p_execute_task_transfer_chain(
									i_task_id => %%s
									, i_transfer_chain_id => %%s
									, i_is_deletion_stage => %%L::boolean
									, i_scheduler_type_name => %L
									, i_scheduled_task_name => %L
									, i_scheduled_task_stage_ord_pos => %s
									, i_max_worker_processes => %s
									, i_polling_interval => %L
									, i_max_run_time => %L
									, i_last_execution_date => %L
								)
							$$
							, ts.task_id 
							, ts.transfer_chain_id
							, ts.is_deletion_stage
						)
					from (
						select distinct
						 	ts.task_id 
							, ts.transfer_chain_id
							, ts.is_deletion_stage
							, ts.chain_order_num
							, ts.are_del_ins_stages_separated
						from 
							${mainSchemaName}.v_task_stage ts
						where 
							ts.project_name = %L
							and ts.task_name = %L
					) ts
					order by 
						ts.chain_order_num
						, ts.is_deletion_stage desc
					$sql$
					, i_scheduler_type_name
					, i_scheduled_task_name
					, i_scheduled_task_stage_ord_pos
					, i_thread_max_count
					, l_polling_interval
					, i_max_run_time
					, ${mainSchemaName}.f_scheduled_task_last_execution_date(
						i_scheduled_task_name => i_scheduled_task_name
					)
					, i_project_name
					, i_task_name
				)
			, i_context_id => '${mainSchemaName}.p_execute_task'::regproc
			, i_operation_instance_id => l_scheduled_task_id::integer
			, i_max_worker_processes => i_thread_max_count
			, i_polling_interval => l_polling_interval
			, i_max_run_time => i_max_run_time
			, i_application_name => '${project_internal_name}'
			, i_close_process_pool_on_completion => true
		)
	;

	if l_scheduled_task_id is not null then
		call
			${mainSchemaName}.p_publish_scheduled_task_monitoring_event(
				i_scheduled_task_id => l_scheduled_task_id
				, i_event_type_name => 'completion'
				, i_event_status_name => 'success'
				, i_event_message => null
			)
		;
	end if
	;

exception
when others then
	get stacked diagnostics
		l_exception_descr = MESSAGE_TEXT
		, l_exception_detail = PG_EXCEPTION_DETAIL
		, l_exception_hint = PG_EXCEPTION_HINT
	;

	if l_scheduled_task_id is not null then
		call
			${mainSchemaName}.p_publish_scheduled_task_monitoring_event(
				i_scheduled_task_id => l_scheduled_task_id
				, i_event_type_name => 'completion'
				, i_event_status_name => 'failure'
				, i_event_message => l_exception_descr
			)
		;
	end if
	;

	raise
	;
end;
/*
declare 
	l_task_commands text[];
	l_checked_exception text;
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
		, case 
			when ts.are_del_ins_stages_separated and i_thread_max_count != 1
			then '''are_del_ins_stages_separated = true'' mode and multi thread mode are incompatible'
		end as exception_text
	into 
		l_task_commands
		, l_checked_exception
	from (
		select distinct
		 	ts.task_id 
			, ts.transfer_chain_id
			, ts.is_deletion_stage
			, ts.chain_order_num
			, ts.are_del_ins_stages_separated
		from 
			${mainSchemaName}.v_task_stage ts
		where 
			ts.project_name = i_project_name
			and ts.task_name = i_task_name
	) ts
	group by 
		ts.are_del_ins_stages_separated
	;

	if l_checked_exception is not null then
		raise exception '%', l_checked_exception;
	end if;
	
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
*/
$procedure$;		

comment on procedure 
	p_execute_task(
		${mainSchemaName}.task.internal_name%type
		, ${mainSchemaName}.project.internal_name%type
		, text
		, text
		, integer
		, integer
		, integer
		, interval
	) 
	is 'Исполнение задачи'
;
