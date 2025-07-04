create or replace view v_scheduled_task
as
with 
	target_scheduled_task as (
		select
			'pgpro_scheduler' as scheduler_type_name
			, t.id
			, t.name
			, t.description
			, t.cron_expr
			, t.commands
			, t.use_same_transaction
			, t.run_as
			, t.onrollback
			, t.max_run_time
			, t.next_time_statement
			, t.last_start_available
			, t.is_disabled
		from 
			${mainSchemaName}.v_pgpro_scheduler_job t
	)
select 
	t.id
	, target_task.id as target_job_id
	, t.internal_name
	, t.name
	, t.description
	, t.job_name 
	, target_task.name as target_job_name
	, t.job_description
	, target_task.description as target_job_description
	, t.cron_expr
	, target_task.cron_expr as target_cron_expr
	, t.command_string
	, target_task.commands as target_command_string
	, t.scheduler_type_name
	, t.project_name
	, t.scheduled_task_name as scheduled_task_name
	, false as is_task_used_single_transaction
	, target_task.use_same_transaction as is_target_task_used_single_transaction
	, t.task_session_user
	, target_task.run_as as target_task_session_user
	, format(
		$$select ${mainSchemaName}.f_cancel_pgpro_scheduler_subjobs(i_scheduled_task_name => '%s')$$
		, t.scheduled_task_name
	) as on_err_cmd
	, target_task.onrollback as target_on_err_cmd
	, make_interval(
		hours => t.timeout_in_hours
	) as max_run_time
	, target_task.max_run_time as target_max_run_time
	, make_interval(
		hours => t.delayed_start_timeout_in_hours
	) as delayed_start_timeout
	, target_task.last_start_available as target_delayed_start_timeout
	, replace(
		t.next_start_time_calc_sttmnt
		, '{{scheduled_task_name}}'
		, t.scheduled_task_name
	) as next_start_time_calc_sttmnt
	, target_task.next_time_statement as target_next_start_time_calc_sttmnt
	, t.retry_interval_in_minutes
	, t.is_disabled
	, target_task.is_disabled as is_target_job_disabled
	, case when t.is_built and target_task.id is not null then true else false end as is_built
from (
	select 
		st.id
		, st.internal_name
		, st.name
		, st.description
		, '${mainSchemaName}.' || p.internal_name || '.' || st.internal_name as job_name 
		, '${project.name}. ' || coalesce(st.name, p.internal_name) || coalesce(': ' || st.description) as job_description
		, st.ordinal_position
		, (
			coalesce(st.cron_expr_minutes, '*')
			|| ' ' || coalesce(st.cron_expr_hours, '*')
			|| ' ' || coalesce(st.cron_expr_dom, '*')
			|| ' ' || coalesce(st.cron_expr_month, '*')
			|| ' ' || coalesce(st.cron_expr_dow, '*')
		) as cron_expr
		, commands.command_string
		, st.task_session_user
		, st.next_start_time_calc_sttmnt
		, st.retry_interval_in_minutes
		, st.timeout_in_hours
		, st.delayed_start_timeout_in_hours
		, sch_type.internal_name as scheduler_type_name
		, p.internal_name as project_name
		, p.internal_name || '.' || st.internal_name as scheduled_task_name
		, st.is_disabled
		, st.is_built
	from 
		${mainSchemaName}.scheduled_task st
	join ${mainSchemaName}.scheduler_type sch_type 
		on sch_type.id = st.scheduler_type_id
	join ${mainSchemaName}.project p 
		on p.id = st.project_id
	left join lateral (
		select 
			string_agg(
				format(
					$$call ${mainSchemaName}.p_execute_task(i_task_name => '%s', i_project_name => '%s', i_scheduler_type_name => '%s', i_scheduled_task_name => '%s.%s', i_scheduled_task_stage_ord_pos => %s, i_thread_max_count => %s, i_wait_for_delay_in_seconds => %s, i_max_run_time => '%s')$$
					, task.internal_name
					, task_project.internal_name
					, sch_type.internal_name
					, p.internal_name
					, st.internal_name
					, task_stage.ordinal_position
					, coalesce(task_stage.thread_max_count, st.thread_max_count)
					, coalesce(task_stage.wait_for_delay_in_seconds, st.wait_for_delay_in_seconds)
					, make_interval(hours => coalesce(task_stage.timeout_in_hours, st.timeout_in_hours))
				) 
				|| case 
					when coalesce(task_stage.thread_max_count, st.thread_max_count) > 1 or is_async then 
						format(
							$$; call ${mainSchemaName}.p_wait_for_scheduled_task_subjobs_completion(i_scheduled_task_name => '%s.%s', i_scheduled_task_stage_ord_pos => %s, i_timeout_in_hours => %s, i_wait_for_delay_in_seconds => %s)$$
							, p.internal_name
							, st.internal_name
							, task_stage.ordinal_position
							, coalesce(task_stage.timeout_in_hours, st.timeout_in_hours)
							, coalesce(task_stage.wait_for_delay_in_seconds, st.wait_for_delay_in_seconds)
						)
					else ''
				end
				, '; ' order by task_stage.ordinal_position
			) as command_string			
		from 
			${mainSchemaName}.scheduled_task_stage task_stage
		join ${mainSchemaName}.task task 
			on task.id = task_stage.task_id
			and task.is_disabled = false
		join ${mainSchemaName}.project task_project 
			on task_project.id = task.project_id
		where 
			task_stage.scheduled_task_id = st.id
			and task_stage.is_disabled = false
			and not exists (
				select 
					1
				from 
					${mainSchemaName}.scheduled_task_stage prev_stage
				where 
					prev_stage.scheduled_task_id = task_stage.scheduled_task_id
					and prev_stage.is_next_stage_executed_recursively 
					and prev_stage.ordinal_position < task_stage.ordinal_position
					and not prev_stage.is_disabled
			)
	) commands on true
) t
left join target_scheduled_task target_task
	on target_task.name = t.job_name
	and target_task.scheduler_type_name = t.scheduler_type_name
;

comment on view v_scheduled_task is 'Плановые задания'
;