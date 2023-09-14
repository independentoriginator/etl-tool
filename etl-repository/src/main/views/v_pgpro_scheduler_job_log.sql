create or replace view v_pgpro_scheduler_job_log
as
with 
	view_obj as (
		select
			pg_get_userbyid(v.relowner) AS view_owner
		from
			pg_catalog.pg_class v
		join pg_catalog.pg_namespace s 
			on s.oid = v.relnamespace
			and s.nspname = '${mainSchemaName}'
		where 
			v.relname = 'v_pgpro_scheduler_job_log'
	)
select 
	t.job_id
	, t.job_name
	, t.scheduled_at
	, t.started
	, t.finished
	, t.run_duration		
	, case when view_obj.view_owner = current_user then t.status else 'done' end as status
	, case when view_obj.view_owner = current_user then t.message else null end as message
from 
	${mainSchemaName}.f_pgpro_scheduler_job_log(
		i_job_id => null
		, i_job_name => null
	) t
	, view_obj
;

comment on view v_pgpro_scheduler_job_log is 'Журнал исполнения плановых заданий pgpro_scheduler';
