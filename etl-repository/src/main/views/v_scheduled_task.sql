create or replace view v_scheduled_task
as
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
	, sch_type.internal_name as scheduler_type_name
	, p.internal_name as project_name
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
				$$call ${mainSchemaName}.p_execute_task(i_task_name => '%s', i_project_name => '%s')$$
				, task.internal_name
				, task_project.internal_name
			)
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
) commands on true
;