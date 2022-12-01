drop view if exists v_pgpro_scheduler_job;

create view v_pgpro_scheduler_job
as
select 
	t.id
	, t.name
	, t.description
	, t.cron_expr
	, t.commands
	, t.use_same_transaction
	, t.run_as
	, t.is_disabled
from 
	${mainSchemaName}.f_pgpro_scheduler_job() t
;						
			