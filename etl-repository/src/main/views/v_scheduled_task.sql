create or replace view v_scheduled_task
as
with
	target_job as ( 
		select 
			'pgpro_scheduler' as scheduler_type_name
			, t.id
			, t.name
			, t.comments as description
			, case when t.active then false else true end as is_disabled  
		from 
			schedule.get_owned_cron() t
	)
select
	t.id
	, t.internal_name
	, t.name
	, t.description
	, t.job_name 
	, t.job_description
	, t.ordinal_position
	, t.cron_expr
	, t.command_string
	, t.scheduler_type_name
	, t.project_name
	, t.is_disabled
	, t.is_built
	, target_job.id as target_id
	, case when target_job.id is not null then true else false end as is_job_exists
	, target_job.name as target_name
	, target_job.description as target_description
	, target_job.is_disabled as target_is_disabled
from (
	select 
		st.id
		, st.internal_name
		, st.name
		, st.description
		, '${mainSchemaName}.' || p.internal_name || '.' || st.internal_name as job_name 
		, '${project.name} . ' || coalesce(st.name, p.internal_name) || coalesce(': ' || st.description) as job_description
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
) t
left join target_job 
	on target_job.name = t.job_name
	and target_job.scheduler_type_name = t.scheduler_type_name
;