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
		string_agg(tr.container, '; ' order by s.ordinal_position) as command_string
	from 
		${mainSchemaName}.scheduled_task_stage s
	join ${mainSchemaName}.task t 
		on t.id = s.task_id
		and t.is_disabled = false
	join ${mainSchemaName}.task_stage ts 
		on ts.task_id = t.id
		and ts.is_disabled = false
	join ${mainSchemaName}.transfer tr 
		on tr.id = ts.transfer_id
	join ${mainSchemaName}.container_type ct 
		on ct.id = tr.container_type_id
		and ct.internal_name = 'sql'
	where 
		s.scheduled_task_id = st.id
		and s.is_disabled = false
) commands on true
;