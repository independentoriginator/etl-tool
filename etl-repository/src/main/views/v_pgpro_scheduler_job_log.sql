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
	${mainSchemaName}.f_pgpro_scheduler_job_log() t
;

