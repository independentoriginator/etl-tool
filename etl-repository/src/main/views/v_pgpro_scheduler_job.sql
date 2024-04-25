create or replace view v_pgpro_scheduler_job
as
select 
	t.id
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
	${mainSchemaName}.f_pgpro_scheduler_job() t
;						
			
comment on view v_pgpro_scheduler_job is 'Плановые задания pgpro_scheduler'
;