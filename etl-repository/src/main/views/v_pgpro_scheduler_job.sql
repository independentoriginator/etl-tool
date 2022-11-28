create or replace view v_pgpro_scheduler_job
as
select 
	t.id
	, t.name
	, t.description
	, t.cron_expr
	, t.commands
	, t.is_disabled
from 
	${mainSchemaName}.f_pgpro_scheduler_job() t
;						
			