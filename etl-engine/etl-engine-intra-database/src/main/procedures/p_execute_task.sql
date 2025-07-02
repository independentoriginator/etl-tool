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

drop procedure if exists 
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
		, i_process_chunks_in_single_transaction boolean = false
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
	l_scheduled_task_stage_rec record;
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

	select 
		s.id
	into 
		l_scheduled_task_stage_rec
	from 
		${mainSchemaName}.scheduled_task_stage s
	where
		s.scheduled_task_id = l_scheduled_task_id
		and s.ordinal_position = i_scheduled_task_stage_ord_pos
	;	
	
	if l_scheduled_task_stage_rec.id is null then
		raise exception 'Unknown scheduled task stage specified: %.%', i_scheduled_task_name, i_scheduled_task_stage_ord_pos;
	end if;

	-- Cancel incompleted subjobs from the previous session
	perform ${mainSchemaName}.f_cancel_pgpro_scheduler_subjobs(
		i_scheduled_task_stage_id => l_scheduled_task_stage_rec.id
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
				task_stage.id = l_scheduled_task_stage_rec.id
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
							do $plpgsql$
							declare 
								l_iteration_rec record;
							begin
								<<sequential_iteration>>
								for l_iteration_rec in (
									select distinct
										ts.task_id
										, ts.transfer_group_id
										, ts.transfer_group_dep_level
									from 
										${mainSchemaName}.v_task_stage ts
									where 
										ts.task_id = %%s
										and ts.transfer_group_chain_id = %%s
									order by 
										ts.transfer_group_dep_level
								)
								loop
									call 
										${mainSchemaName}.p_execute_task_transfer_group(
											i_task_id => l_iteration_rec.task_id
											, i_transfer_group_id => l_iteration_rec.transfer_group_id
											, i_scheduler_type_name => %L
											, i_scheduled_task_name => %L
											, i_scheduled_task_stage_ord_pos => %s
											, i_max_worker_processes => %s
											, i_polling_interval => %L
											, i_max_run_time => %L
											, i_process_chunks_in_single_transaction => %L::boolean
										)
									;
								end loop sequential_iteration
								;
							end
							$plpgsql$
							;
							$$
							, ts.task_id 
							, ts.transfer_group_chain_id
						)
					from (
						select distinct
						 	ts.task_id
							, ts.transfer_group_chain_id
						from 
							${mainSchemaName}.v_task_stage ts
						where 
							ts.project_name = %L
							and ts.task_name = %L
					) ts
					$sql$
					, i_scheduler_type_name
					, i_scheduled_task_name
					, i_scheduled_task_stage_ord_pos
					, i_thread_max_count
					, l_polling_interval
					, i_max_run_time
					, i_process_chunks_in_single_transaction
					, i_project_name
					, i_task_name
				)
			, i_context_id => '${mainSchemaName}.p_execute_task'::regproc
			, i_operation_instance_id => l_scheduled_task_id::integer
			, i_max_worker_processes => i_thread_max_count
			, i_single_transaction => i_process_chunks_in_single_transaction
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

	for l_scheduled_task_stage_rec in (
		select 
			s.ordinal_position
			, t.internal_name as task_name
			, p.internal_name as project_name
		from 
			${mainSchemaName}.scheduled_task_stage s
		join ${mainSchemaName}.scheduled_task_stage prev_s
			on prev_s.scheduled_task_id = s.scheduled_task_id
			and prev_s.ordinal_position = i_scheduled_task_stage_ord_pos
			and prev_s.is_next_stage_executed_recursively
			and prev_s.is_disabled = false
		join ${mainSchemaName}.task t 
			on t.id = s.task_id
			and t.is_disabled = false
		join ${mainSchemaName}.project p 
			on p.id = t.project_id
		where
			s.scheduled_task_id = l_scheduled_task_id
			and s.ordinal_position > i_scheduled_task_stage_ord_pos
			and s.is_disabled = false
		order by 
			s.ordinal_position
		limit 
			1
	)
	loop
		call
			${mainSchemaName}.p_execute_task(
				i_task_name => l_scheduled_task_stage_rec.task_name
				, i_project_name => l_scheduled_task_stage_rec.project_name
				, i_scheduler_type_name => i_scheduler_type_name
				, i_scheduled_task_name => i_scheduled_task_name
				, i_scheduled_task_stage_ord_pos => l_scheduled_task_stage_rec.ordinal_position
				, i_thread_max_count => i_thread_max_count
				, i_wait_for_delay_in_seconds => i_wait_for_delay_in_seconds
				, i_max_run_time => i_max_run_time
				, i_process_chunks_in_single_transaction => i_process_chunks_in_single_transaction
			)
		;
	end loop
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
end
;
$procedure$
;		

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
		, boolean
	) 
	is 'Исполнение задачи'
;
