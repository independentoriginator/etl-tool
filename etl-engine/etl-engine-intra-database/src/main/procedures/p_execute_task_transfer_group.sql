drop procedure if exists 
	p_execute_task_transfer_group(
		${mainSchemaName}.task.id%type
		, integer
		, ${mainSchemaName}.transfer_group.id%type
		, text
		, text
		, integer
		, integer
		, interval
		, interval
	)
;

drop procedure if exists 
	p_execute_task_transfer_group(
		${mainSchemaName}.task.id%type
		, integer
		, ${mainSchemaName}.transfer_group.id%type
		, text
		, text
		, integer
		, integer
		, interval
		, interval
		, boolean
	)
;

drop procedure if exists 
	p_execute_task_transfer_group(
		${mainSchemaName}.task.id%type
		, integer
		, ${mainSchemaName}.transfer_group.id%type
		, text
		, text
		, integer
		, integer
		, interval
		, interval
		, boolean
	)
;

create or replace procedure 
	p_execute_task_transfer_group(
		i_task_id ${mainSchemaName}.task.id%type
		, i_transfer_group_id ${mainSchemaName}.transfer_group.id%type
		, i_scheduler_type_name text = null
		, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
		, i_scheduled_task_stage_ord_pos integer = 0
		, i_max_worker_processes integer = 1
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
		, i_process_chunks_in_single_transaction boolean = false
	)
language plpgsql
as $procedure$
declare
	l_scheduled_task_id ${mainSchemaName}.scheduled_task.id%type := 
		${mainSchemaName}.f_scheduled_task_id(
			i_scheduled_task_name => i_scheduled_task_name
		)
	;
begin
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
									, i_process_chunks_in_single_transaction => %L::boolean
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
							ts.task_id = %s
							and ts.transfer_group_id = %s
					) ts
					order by 
						ts.chain_order_num
						, ts.is_deletion_stage desc
					$sql$
					, i_scheduler_type_name
					, i_scheduled_task_name
					, i_scheduled_task_stage_ord_pos
					, i_max_worker_processes
					, i_polling_interval
					, i_max_run_time
					, ${mainSchemaName}.f_scheduled_task_last_execution_date(
						i_scheduled_task_name => i_scheduled_task_name
					)
					, i_process_chunks_in_single_transaction
					, i_task_id
					, i_transfer_group_id
				)
			, i_context_id => '${mainSchemaName}.p_execute_task_transfer_group'::regproc
			, i_operation_instance_id => 
				hashtext(
					concat_ws(
						'.'
						, l_scheduled_task_id::text
						, i_transfer_group_id::text
					)
				)
			, i_max_worker_processes => i_max_worker_processes
			, i_single_transaction => i_process_chunks_in_single_transaction
			, i_polling_interval => i_polling_interval
			, i_max_run_time => i_max_run_time
			, i_application_name => '${project_internal_name}'
			, i_close_process_pool_on_completion => true
		)
	;
end
$procedure$;			

comment on procedure 
	p_execute_task_transfer_group(
		${mainSchemaName}.task.id%type
		, ${mainSchemaName}.transfer_group.id%type
		, text
		, text
		, integer
		, integer
		, interval
		, interval
		, boolean
	) 
	is 'Исполнение группы перемещений задачи'
;
