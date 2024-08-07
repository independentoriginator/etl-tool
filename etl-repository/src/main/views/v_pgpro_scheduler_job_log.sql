create or replace view v_pgpro_scheduler_job_log
as
select 
	t.job_id
	, t.job_name
	, t.scheduled_at
	, t.started
	, t.finished
	, t.run_duration		
	, t.status
	, t.message
from 
	${mainSchemaName}.f_pgpro_scheduler_job_log(
		i_job_id => null
		, i_job_name => null
	) t
where 
	t.job_name like '${mainSchemaName}%'
	and (t.message is null or t.message not ilike 'max instances limit reached%')
;

comment on view v_pgpro_scheduler_job_log is 'Журнал исполнения плановых заданий pgpro_scheduler';
